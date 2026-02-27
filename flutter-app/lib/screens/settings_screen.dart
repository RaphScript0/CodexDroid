import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/websocket_service.dart';

class SettingsScreen extends StatefulWidget {
  final WebSocketService websocketService;
  final String initialIp;
  final String initialPort;

  const SettingsScreen({
    super.key,
    required this.websocketService,
    required this.initialIp,
    required this.initialPort,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _ipController;
  late TextEditingController _portController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialIp);
    _portController = TextEditingController(text: widget.initialPort);
    _loadSettings();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('server_ip') ?? widget.initialIp;
      _portController.text = prefs.getString('server_port') ?? widget.initialPort;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final ip = _ipController.text.trim();
    final port = _portController.text.trim();

    if (ip.isEmpty || port.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    // Validate IP format (basic check)
    final ipRegex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (!ipRegex.hasMatch(ip)) {
      _showError('Please enter a valid IP address');
      return;
    }

    // Validate port
    final portNum = int.tryParse(port);
    if (portNum == null || portNum < 1 || portNum > 65535) {
      _showError('Please enter a valid port (1-65535)');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_ip', ip);
      await prefs.setString('server_port', port);

      // Update websocket service with new config
      widget.websocketService.updateServerConfig(ip, port);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to save settings: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'WebSocket Server Configuration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Server IP Address',
                hintText: '192.168.1.100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Server Port',
                hintText: '8080',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text('Save & Reconnect'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Connection Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatusRow('Current IP', _ipController.text),
            _buildStatusRow('Current Port', _portController.text),
            _buildStatusRow(
              'Connection State',
              _getWsConnectionStateText(),
              valueColor: _getWsConnectionStateColor(),
            ),
            const SizedBox(height: 32),
            const Text(
              'About',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatusRow('App Version', '1.0.0'),
            _buildStatusRow('Framework', 'Flutter'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 15),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  String _getWsConnectionStateText() {
    switch (widget.websocketService.connectionState) {
      case WsConnectionState.connected:
        return 'Connected ✓';
      case WsConnectionState.connecting:
        return 'Connecting...';
      case WsConnectionState.error:
        return 'Error ✗';
      case WsConnectionState.disconnected:
        return 'Disconnected';
    }
  }

  Color _getWsConnectionStateColor() {
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
}
