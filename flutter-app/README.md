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

## CI/CD: Signed APK Build

This repository includes a GitHub Actions workflow that automatically builds a **signed APK** on every push to `main` and on manual dispatch.

### Workflow Location

`.github/workflows/android-release.yml`

### Required Secrets

Configure these secrets in your GitHub repository settings (`Settings → Secrets and variables → Actions → New repository secret`):

| Secret Name | Description |
|-------------|-------------|
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded keystore file (`keystore.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias within the keystore |
| `ANDROID_KEY_PASSWORD` | Key password |

### How to Generate Keystore & Base64

```bash
# 1. Generate a new keystore (one-time)
keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias your_alias

# 2. Encode to base64 (for GitHub secret)
base64 keystore.jks > keystore.jks.base64

# 3. Copy the content of keystore.jks.base64 and paste as ANDROID_KEYSTORE_BASE64 secret
```

### Running the Workflow

- **Automatic**: Runs on every push to `main`
- **Manual**: Go to `Actions → Android Release (Signed APK) → Run workflow`

### Downloading the APK

1. Navigate to the workflow run in GitHub Actions
2. Scroll to the "Artifacts" section
3. Click `app-release-signed` to download the signed APK
4. APK is retained for 30 days

### Output

- **Artifact Name**: `app-release-signed`
- **File**: `app-release.apk` (signed release build)
- **Retention**: 30 days

## License

MIT
