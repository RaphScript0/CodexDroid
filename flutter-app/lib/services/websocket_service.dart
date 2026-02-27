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

  WebSocketService({
    required this.serverIp,
    required this.serverPort,
  });

  WsConnectionState get connectionState => _connectionState;
  List<String> get messages => List.unmodifiable(_messages);
  Stream<String> get messageStream => _messageController.stream;

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

  void sendMessage(String message) {
    if (_connectionState != WsConnectionState.connected || _channel == null) {
      return;
    }
    
    _channel!.sink.add(message);
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

  void _handleMessage(dynamic message) {
    final String msg = message.toString();
    _messages.add(msg);
    _messageController.add(msg);
    notifyListeners();
  }

  void _handleError(dynamic error) {
    debugPrint('WebSocket error: $error');
    _setConnectionState(WsConnectionState.error);
    
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
