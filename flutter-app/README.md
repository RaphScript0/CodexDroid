# CodexAndroid Flutter App

Flutter-based Android app for real-time chat interface with Codex CLI bridge server.

## Features

- **Chat UI**: Message bubbles with user/server distinction
- **Real-time Streaming**: Incremental rendering of Codex responses
- **WebSocket Client**: Connect/disconnect/reconnect with auto-recovery
- **Settings Screen**: Configure server IP and port (persisted locally)
- **Connection State**: Visual indicator (connected/disconnected/connecting/error)

## Architecture

```
lib/
├── main.dart                 # App entry point, navigation
├── services/
│   └── websocket_service.dart  # WebSocket connection management
└── screens/
    ├── chat_screen.dart        # Chat UI with message bubbles
    └── settings_screen.dart    # Server configuration
```

## Dependencies

- `web_socket_channel`: WebSocket client
- `shared_preferences`: Local settings persistence
- `flutter_lints`: Code quality

## Setup

### Prerequisites

- Flutter SDK 3.0+
- Android Studio / VS Code with Flutter extension
- Android device or emulator

### Installation

```bash
cd flutter-app
flutter pub get
```

### Running

```bash
# Run on connected device/emulator
flutter run

# Build APK
flutter build apk --release

# Build for specific architecture
flutter build apk --split-per-abi
```

### Configuration

1. Launch the app
2. Navigate to Settings tab
3. Enter your bridge server IP and port (default: 192.168.1.100:8080)
4. Tap "Save & Reconnect"

## Usage

### Chat Screen

- **Connection Indicator**: Top bar shows current connection state
  - 🟢 Green: Connected
  - 🟠 Orange: Connecting
  - 🔴 Red: Error
  - ⚪ Grey: Disconnected

- **Message Bubbles**:
  - Blue (right): User messages
  - Grey (left): Server responses

- **Controls**:
  - Text input + send button
  - Refresh icon: Manual reconnect
  - Delete icon: Clear chat history

### Settings Screen

- Server IP: IPv4 address format validation
- Server Port: 1-65535 range validation
- Settings persist across app restarts
- Save triggers immediate reconnect with new config

## Testing

```bash
# Run all tests
flutter test

# Run with coverage
flutter test --coverage

# Run specific test file
flutter test test/websocket_service_test.dart
```

### Test Coverage

- **Unit Tests**: WebSocketService functionality
- **Widget Tests**: ChatScreen UI components
- **Edge Cases**: Empty messages, connection states, input validation

## Connection Flow

1. App starts with saved/recent server config
2. User initiates connection (or auto-connect on save)
3. WebSocket connects to `ws://<ip>:<port>`
4. Messages stream in real-time
5. On disconnect: auto-reconnect after 3 seconds
6. On error: retry with exponential backoff

## WebSocket Protocol

The app expects a standard WebSocket server that:
- Accepts text messages
- Sends text responses
- Handles graceful close
- Supports reconnection

Example server message format:
```
user: <message>    # User-sent messages (echo/local)
<response>         # Server responses (streaming or complete)
```

## Troubleshooting

### Connection Issues

- Verify server is running and accessible
- Check firewall rules on server machine
- Ensure IP/port are correct in settings
- Try local network vs. localhost (127.0.0.1 won't work from device)

### Build Issues

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run

# Check Flutter setup
flutter doctor
```

## License

MIT
