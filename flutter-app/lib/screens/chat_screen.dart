import 'package:flutter/material.dart';
import '../services/websocket_service.dart';

class ChatScreen extends StatefulWidget {
  final WebSocketService websocketService;

  const ChatScreen({super.key, required this.websocketService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isStreaming = false;
  String _currentStreamingMessage = '';

  @override
  void initState() {
    super.initState();
    // List rebuilds are handled by ListenableBuilder for efficient updates
    _setupMessageListener();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setupMessageListener() {
    widget.websocketService.messageStream.listen((message) {
      setState(() {
        if (_isStreaming) {
          _currentStreamingMessage += message;
        } else {
          _currentStreamingMessage = message;
        }
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    widget.websocketService.addMessage('user: $text');
    widget.websocketService.sendMessage(text);
    _controller.clear();
    
    setState(() {
      _isStreaming = true;
      _currentStreamingMessage = '';
    });

    _scrollToBottom();
  }

  void _toggleConnection() {
    final state = widget.websocketService.connectionState;
    if (state == WsConnectionState.connected) {
      widget.websocketService.disconnect();
    } else {
      widget.websocketService.connect();
    }
  }

  Color _getConnectionColor() {
    switch (widget.websocketService.connectionState) {
      case WsConnectionState.connected:
        return Colors.green;
      case WsConnectionState.connecting:
        return Colors.orange;
      case WsConnectionState.error:
        return Colors.red;
      case WsConnectionState.disconnected:
        return Colors.grey;
    }
  }

  String _getConnectionText() {
    switch (widget.websocketService.connectionState) {
      case WsConnectionState.connected:
        return 'Connected';
      case WsConnectionState.connecting:
        return 'Connecting...';
      case WsConnectionState.error:
        return 'Error';
      case WsConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: widget.websocketService,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _getConnectionColor(),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(_getConnectionText()),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => widget.websocketService.reconnect(),
            tooltip: 'Reconnect',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => widget.websocketService.clearMessages(),
            tooltip: 'Clear chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListenableBuilder(
              listenable: widget.websocketService,
              builder: (context, _) {
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.websocketService.messages.length,
                  itemBuilder: (context, index) {
                    final message = widget.websocketService.messages[index];
                    final isUser = message.startsWith('user:');
                    return _buildMessageBubble(message, isUser);
                  },
                );
              },
            ),
          ),
          if (_isStreaming && _currentStreamingMessage.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentStreamingMessage,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String message, bool isUser) {
    final actualMessage = isUser ? message.substring(5) : message;
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          actualMessage,
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
              enabled: widget.websocketService.connectionState == WsConnectionState.connected,
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: widget.websocketService,
            builder: (context, _) {
              return CircleAvatar(
                backgroundColor: widget.websocketService.connectionState == WsConnectionState.connected
                    ? Colors.blue
                    : Colors.grey,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: widget.websocketService.connectionState == WsConnectionState.connected
                      ? _sendMessage
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
