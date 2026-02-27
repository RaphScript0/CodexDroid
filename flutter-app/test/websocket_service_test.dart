import 'package:flutter_test/flutter_test.dart';
import 'package:codex_android/services/websocket_service.dart';

void main() {
  group('WebSocketService', () {
    late WebSocketService service;

    setUp(() {
      service = WebSocketService(
        serverIp: '192.168.1.100',
        serverPort: '8080',
      );
    });

    tearDown(() {
      service.dispose();
    });

    test('initial state is disconnected', () {
      expect(service.connectionState, ConnectionState.disconnected);
      expect(service.messages, isEmpty);
    });

    test('serverIp and serverPort are set correctly', () {
      expect(service.serverIp, '192.168.1.100');
      expect(service.serverPort, '8080');
    });

    test('messages list is immutable', () {
      service.addMessage('test message');
      expect(service.messages.length, 1);
      
      // Try to modify the returned list
      expect(() => service.messages.add('another'), throwsUnsupportedError);
    });

    test('addMessage adds message to list', () {
      service.addMessage('hello');
      expect(service.messages.length, 1);
      expect(service.messages.first, 'hello');
    });

    test('addMessage notifies listeners', () {
      bool notified = false;
      service.addListener(() {
        notified = true;
      });
      
      service.addMessage('test');
      expect(notified, isTrue);
    });

    test('clearMessages removes all messages', () {
      service.addMessage('msg1');
      service.addMessage('msg2');
      service.addMessage('msg3');
      
      expect(service.messages.length, 3);
      
      service.clearMessages();
      
      expect(service.messages, isEmpty);
    });

    test('clearMessages notifies listeners', () {
      bool notified = false;
      service.addListener(() {
        notified = true;
      });
      
      service.addMessage('test');
      service.clearMessages();
      
      expect(notified, isTrue);
    });

    test('multiple messages are preserved in order', () {
      service.addMessage('first');
      service.addMessage('second');
      service.addMessage('third');
      
      expect(service.messages.length, 3);
      expect(service.messages[0], 'first');
      expect(service.messages[1], 'second');
      expect(service.messages[2], 'third');
    });

    test('messageStream broadcasts messages', () async {
      final receivedMessages = <String>[];
      service.messageStream.listen((msg) {
        receivedMessages.add(msg);
      });

      service.addMessage('msg1');
      service.addMessage('msg2');
      
      // Allow async processing
      await Future.delayed(const Duration(milliseconds: 100));
      
      expect(receivedMessages.length, 2);
      expect(receivedMessages[0], 'msg1');
      expect(receivedMessages[1], 'msg2');
    });
  });

  group('ConnectionState enum', () {
    test('has all expected states', () {
      expect(ConnectionState.values.length, 4);
      expect(ConnectionState.values.contains(ConnectionState.disconnected), isTrue);
      expect(ConnectionState.values.contains(ConnectionState.connecting), isTrue);
      expect(ConnectionState.values.contains(ConnectionState.connected), isTrue);
      expect(ConnectionState.values.contains(ConnectionState.error), isTrue);
    });
  });
}
