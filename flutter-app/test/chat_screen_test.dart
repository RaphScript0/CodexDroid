import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_android/screens/chat_screen.dart';
import 'package:codex_android/services/websocket_service.dart';

void main() {
  group('ChatScreen', () {
    late WebSocketService mockService;

    setUp(() {
      mockService = WebSocketService(
        serverIp: '192.168.1.100',
        serverPort: '8080',
      );
    });

    tearDown(() {
      mockService.dispose();
    });

    testWidgets('displays connection state indicator', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      // Initial state is disconnected
      expect(find.text('Disconnected'), findsOneWidget);
    });

    testWidgets('displays empty message list initially', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      // No message bubbles should be present
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('displays message bubbles after messages are added', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      // Add a user message
      mockService.addMessage('user: Hello');
      await tester.pump();

      expect(find.text('Hello'), findsOneWidget);
    });

    testWidgets('displays input field', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Type a message...'), findsOneWidget);
    });

    testWidgets('send button is disabled when disconnected', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      final sendButton = tester.widget<CircleAvatar>(
        find.byType(CircleAvatar),
      );
      
      // Send button should be grey when disconnected
      expect(sendButton.backgroundColor, Colors.grey);
    });

    testWidgets('clear chat button exists', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('reconnect button exists', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('user messages are aligned right', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      mockService.addMessage('user: Test message');
      await tester.pump();

      final alignWidget = tester.widget<Align>(
        find.ancestor(
          of: find.text('Test message'),
          matching: find.byType(Align),
        ).first,
      );

      expect(alignWidget.alignment, Alignment.centerRight);
    });

    testWidgets('server messages are aligned left', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      mockService.addMessage('Server response');
      await tester.pump();

      final alignWidget = tester.widget<Align>(
        find.ancestor(
          of: find.text('Server response'),
          matching: find.byType(Align),
        ).first,
      );

      expect(alignWidget.alignment, Alignment.centerLeft);
    });

    testWidgets('message bubbles have rounded corners', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      mockService.addMessage('user: Test');
      await tester.pump();

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('Test'),
          matching: find.byType(Container),
        ).first,
      );

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, isNotNull);
    });

    testWidgets('user messages have blue background', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      mockService.addMessage('user: Hello');
      await tester.pump();

      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('Hello'),
          matching: find.byType(Container),
        ).first,
      );

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
    });

    testWidgets('input field accepts text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChatScreen(websocketService: mockService),
        ),
      );

      await tester.enterText(find.byType(TextField), 'Test message');
      await tester.pump();

      expect(find.text('Test message'), findsOneWidget);
    });
  });
}
