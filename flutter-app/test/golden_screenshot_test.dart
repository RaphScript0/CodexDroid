import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:codex_android/screens/chat_screen.dart';
import 'package:codex_android/screens/settings_screen.dart';
import 'package:codex_android/services/websocket_service.dart';
import 'dart:io';
import 'dart:ui' as ui;

void main() {
  testWidgets('ChatScreen golden screenshot', (WidgetTester tester) async {
    final service = WebSocketService(serverIp: '192.168.1.100', serverPort: '8765');
    service.addMessage('user: Hello!');
    service.addMessage('server: Server response here');
    
    final boundaryKey = GlobalKey();
    
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          home: ChatScreen(websocketService: service),
        ),
      ),
    );
    
    await tester.pump();
    
    final boundary = tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    
    final dir = Directory('/tmp/codexdroid/test-report/ran/screenshots');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/chat_screen.png');
    file.writeAsBytesSync(pngBytes);
    print('Saved: ${file.path} (${pngBytes.length} bytes)');
  });
  
  testWidgets('SettingsScreen golden screenshot', (WidgetTester tester) async {
    final service = WebSocketService(serverIp: '192.168.1.100', serverPort: '8765');
    
    final boundaryKey = GlobalKey();
    
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          home: SettingsScreen(
            websocketService: service,
            initialIp: '192.168.1.100',
            initialPort: '8765',
          ),
        ),
      ),
    );
    
    await tester.pump();
    
    final boundary = tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    
    final dir = Directory('/tmp/codexdroid/test-report/ran/screenshots');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/settings_screen.png');
    file.writeAsBytesSync(pngBytes);
    print('Saved: ${file.path} (${pngBytes.length} bytes)');
  });
}
