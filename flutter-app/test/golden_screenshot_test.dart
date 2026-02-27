import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_android/screens/chat_screen.dart';
import 'package:codex_android/screens/settings_screen.dart';
import 'package:codex_android/services/websocket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:ui' as ui;

void main() {
  testWidgets('ChatScreen golden screenshot', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'server_ip': '192.168.1.100',
      'server_port': '8765',
    });

    final service = WebSocketService(serverIp: '192.168.1.100', serverPort: '8765');
    service.setConnectionStateForTesting(WsConnectionState.connected);
    service.addMessage('user: Hello!');
    service.addMessage('server: Server response here');
    service.addMessage('user: Testing the chat interface');
    service.addMessage('server: This is a longer response to test text wrapping');
    
    final boundaryKey = GlobalKey();
    
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: Container(
            width: 800,
            height: 600,
            color: Colors.white,
            child: ChatScreen(websocketService: service),
          ),
        ),
      ),
    );
    
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    
    final boundary = tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    
    final dir = Directory('/tmp/codexdroid/test-report/ran/screenshots');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/chat_screen.png');
    file.writeAsBytesSync(pngBytes);
    print('Saved chat_screen.png: ${file.path} (${pngBytes.length} bytes)');
    
    expect(pngBytes.length, greaterThan(1000));
  });
  
  testWidgets('SettingsScreen golden screenshot', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'server_ip': '192.168.1.100',
      'server_port': '8765',
    });

    final service = WebSocketService(serverIp: '192.168.1.100', serverPort: '8765');
    service.setConnectionStateForTesting(WsConnectionState.connected);
    
    final boundaryKey = GlobalKey();
    
    // Use taller container to avoid overflow
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundaryKey,
          child: Container(
            width: 800,
            height: 1200,
            color: Colors.white,
            child: SettingsScreen(
              websocketService: service,
              initialIp: '192.168.1.100',
              initialPort: '8765',
            ),
          ),
        ),
      ),
    );
    
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump();
    
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Server IP Address'), findsOneWidget);
    expect(find.text('Server Port'), findsOneWidget);
    
    final boundary = tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    
    final dir = Directory('/tmp/codexdroid/test-report/ran/screenshots');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/settings_screen.png');
    file.writeAsBytesSync(pngBytes);
    print('Saved settings_screen.png: ${file.path} (${pngBytes.length} bytes)');
    
    expect(pngBytes.length, greaterThan(5000));
  });
}
