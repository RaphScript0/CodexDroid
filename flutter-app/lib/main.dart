import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:codex_android/services/websocket_service.dart';
import 'package:codex_android/screens/chat_screen.dart';
import 'package:codex_android/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load saved settings
  final prefs = await SharedPreferences.getInstance();
  final serverIp = prefs.getString('server_ip') ?? '192.168.1.100';
  final serverPort = prefs.getString('server_port') ?? '8080';
  
  runApp(CodexDroidApp(
    initialServerIp: serverIp,
    initialServerPort: serverPort,
  ));
}

class CodexDroidApp extends StatefulWidget {
  final String initialServerIp;
  final String initialServerPort;

  const CodexDroidApp({
    super.key,
    required this.initialServerIp,
    required this.initialServerPort,
  });

  @override
  State<CodexDroidApp> createState() => _CodexDroidAppState();
}

class _CodexDroidAppState extends State<CodexDroidApp> {
  late WebSocketService _websocketService;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _websocketService = WebSocketService(
      serverIp: widget.initialServerIp,
      serverPort: widget.initialServerPort,
    );
  }

  @override
  void dispose() {
    _websocketService.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CodexDroid',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            ChatScreen(websocketService: _websocketService),
            SettingsScreen(
              websocketService: _websocketService,
              initialIp: widget.initialServerIp,
              initialPort: widget.initialServerPort,
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.chat),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
          currentIndex: _currentIndex,
          onTap: _onTabTapped,
        ),
      ),
    );
  }
}
