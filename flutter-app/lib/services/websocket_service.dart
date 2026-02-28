import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum WsConnectionState { disconnected, connecting, connected, error }

class WebSocketService extends ChangeNotifier {
  final String serverIp;
  final String serverPort;
  
  WebSocketChannel? _channel;
  WsConnectionState _connectionState = WsConnectionState.disconnected;
  final List<String> _messages = [];
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  String? _lastError;
  String? _sessionId;
  int _messageId = 1;
  final Map<int, Completer> _pendingRequests = {};

  WebSocketService({
    required this.serverIp,
    required this.serverPort,
  });

  WsConnectionState get connectionState => _connectionState;
  List<String> get messages => List.unmodifiable(_messages);
  Stream<String> get messageStream => _messageController.stream;
  String? get lastError => _lastError;
  String? get sessionId => _sessionId;
  
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  void connect() {
    if (_connectionState == WsConnectionState.connected || 
        _connectionState == WsConnectionState.connecting) {
      return;
    }

    _setConnectionState(WsConnectionState.connecting);
    
    try {
      final uri = Uri.parse('ws://$serverIp:$serverPort');
      _channel = WebSocketChannel.connect(uri);
      
      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          _handleError(error);
        },
        onDone: () {
          _handleDisconnect();
        },
      );
      
      // Assume connected after successful connection setup
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_connectionState == WsConnectionState.connecting) {
          _setConnectionState(WsConnectionState.connected);
          // Create session after connection
          _createSession();
        }
      });
    } catch (e) {
      _handleError(e);
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    
    // Close session if exists
    if (_sessionId != null) {
      _closeSession();
    }
    
    _channel?.sink.close();
    _channel = null;
    _setConnectionState(WsConnectionState.disconnected);
  }

  void reconnect() {
    if (_isReconnecting) return;
    
    _isReconnecting = true;
    disconnect();
    
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      _isReconnecting = false;
      connect();
    });
  }

  /// Send a user message to Codex via the bridge
  void sendMessage(String message) {
    if (_connectionState != WsConnectionState.connected || _channel == null) {
      return;
    }
    
    if (_sessionId == null) {
      debugPrint('[WebSocketService] No session ID, cannot send message');
      return;
    }
    
    // Wrap message in JSON-RPC send with realtime event format
    final realtimeEvent = {
      'jsonrpc': '2.0',
      'method': 'conversation.item.create',
      'params': {
        'item': {
          'type': 'message',
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text': message
            }
          ]
        }
      }
    };
    
    final request = {
      'jsonrpc': '2.0',
      'method': 'send',
      'params': {
        'sessionId': _sessionId,
        'message': realtimeEvent
      },
      'id': _messageId++
    };
    
    _channel!.sink.add(jsonEncode(request));
  }

  void addMessage(String message) {
    _messages.add(message);
    _messageController.add(message);
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  void updateServerConfig(String ip, String port) {
    disconnect();
    Future.delayed(const Duration(milliseconds: 100), () {
      connect();
    });
  }

  /// Create a new session with the bridge server
  Future<void> _createSession() async {
    if (_channel == null || _connectionState != WsConnectionState.connected) {
      return;
    }
    
    final requestId = _messageId++;
    final request = {
      'jsonrpc': '2.0',
      'method': 'session.create',
      'id': requestId
    };
    
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[requestId] = completer;
    
    _channel!.sink.add(jsonEncode(request));
    
    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Session creation timeout'),
      );
      
      _sessionId = result['sessionId'];
      debugPrint('[WebSocketService] Session created: $_sessionId');
      
      // Notify listeners that session is ready
      _messageController.add('system: Session connected');
    } catch (e) {
      debugPrint('[WebSocketService] Session creation failed: $e');
      _lastError = 'Failed to create session: $e';
      _setConnectionState(WsConnectionState.error);
    }
  }

  /// Close the current session
  Future<void> _closeSession() async {
    if (_sessionId == null || _channel == null) {
      return;
    }
    
    final requestId = _messageId++;
    final request = {
      'jsonrpc': '2.0',
      'method': 'session.close',
      'params': {
        'sessionId': _sessionId
      },
      'id': requestId
    };
    
    _channel!.sink.add(jsonEncode(request));
    _sessionId = null;
    debugPrint('[WebSocketService] Session closed');
  }

  void _handleMessage(dynamic message) {
    final String msg = message.toString();
    
    try {
      final data = jsonDecode(msg);
      
      // Handle JSON-RPC responses
      if (data['id'] != null && _pendingRequests.containsKey(data['id'])) {
        final completer = _pendingRequests.remove(data['id']);
        if (data['error'] != null) {
          completer?.completeError(Exception(data['error']['message']));
        } else if (data['result'] != null) {
          completer?.complete(data['result']);
        }
        return;
      }
      
      // Handle server notifications
      if (data['method'] != null) {
        switch (data['method']) {
          case 'stream':
            _handleStream(data['params']);
            break;
          case 'conversation.item.added':
            _handleItemAdded(data['params']);
            break;
          case 'connected':
            debugPrint('[WebSocketService] Connected with clientId: ${data['params']['clientId']}');
            break;
          case 'shutdown':
            debugPrint('[WebSocketService] Server shutting down: ${data['params']['reason']}');
            _lastError = 'Server shutting down';
            _setConnectionState(WsConnectionState.error);
            break;
        }
        return;
      }
      
      // Fallback: treat as raw message
      _messages.add(msg);
      _messageController.add(msg);
      notifyListeners();
    } catch (e) {
      // Not JSON, treat as raw message
      _messages.add(msg);
      _messageController.add(msg);
      notifyListeners();
    }
  }

  void _handleStream(Map<String, dynamic> params) {
    // Extract streaming text from Codex response
    final result = params['result'];
    if (result != null) {
      final output = result['output'] ?? result['text'] ?? result['content'];
      if (output != null) {
        final text = output is String ? output : jsonEncode(output);
        _messages.add(text);
        _messageController.add(text);
        notifyListeners();
      }
    }
  }

  void _handleItemAdded(Map<String, dynamic> params) {
    // Handle conversation.item.added events
    final item = params['item'];
    if (item != null) {
      final role = item['role'];
      final content = item['content'];
      if (role == 'assistant' && content != null && content is List && content.isNotEmpty) {
        final textContent = content.firstWhere(
          (c) => c['type'] == 'output_text' || c['type'] == 'text',
          orElse: () => null,
        );
        if (textContent != null) {
          final text = textContent['text'] ?? textContent['content'] ?? '';
          if (text.isNotEmpty) {
            _messages.add(text);
            _messageController.add(text);
            notifyListeners();
          }
        }
      }
    }
  }

  void _handleError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _lastError = error.toString();
    _setConnectionState(WsConnectionState.error);
    notifyListeners();
    
    // Auto-reconnect on error
    if (!_isReconnecting) {
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        if (_connectionState != WsConnectionState.connected) {
          reconnect();
        }
      });
    }
  }

  void _handleDisconnect() {
    if (_connectionState == WsConnectionState.connected) {
      _setConnectionState(WsConnectionState.disconnected);
      
      // Auto-reconnect on unexpected disconnect
      if (!_isReconnecting) {
        _reconnectTimer = Timer(const Duration(seconds: 3), () {
          if (_connectionState != WsConnectionState.connected) {
            reconnect();
          }
        });
      }
    }
  }

  void _setConnectionState(WsConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _messageController.close();
    super.dispose();
  }
}
