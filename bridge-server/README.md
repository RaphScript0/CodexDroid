# CodexDroid Bridge Server

Lightweight WebSocket proxy server that wraps `codex app-server` and exposes it to clients over WebSocket with JSON-RPC interface.

## Features

- **Session Management**: Create, manage, and close sessions with Codex app-server
- **Real-time Streaming**: Stream Codex responses back to clients instantly
- **JSON-RPC 2.0**: Clean protocol for all operations
- **Reconnect Support**: Automatic session cleanup and reconnection handling
- **Graceful Shutdown**: Clean connection termination on server shutdown
- **Health Monitoring**: HTTP health endpoint for status checks

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Client    │────▶│  Bridge Server   │────▶│ Codex App-Server│
│  (WS 4501)  │     │   (Proxy/WS)     │     │   (WS 4500)     │
└─────────────┘     └──────────────────┘     └─────────────────┘
                          │
                          ▼
                   ┌─────────────┐
                   │ Health HTTP │
                   │  (Port 4502)│
                   └─────────────┘
```

## Installation

```bash
cd bridge-server
npm install
```

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `BRIDGE_HOST` | `0.0.0.0` | Host/interface to bind for client connections |
| `BRIDGE_PORT` | `4501` | WebSocket port for client connections |
| `CODEX_APP_SERVER_URL` | `ws://127.0.0.1:4500` | Codex app-server WebSocket URL |
| `START_APP_SERVER` | `true` | Whether to spawn `codex app-server` process |

## Usage

### Start the Server

```bash
# Default (bind all interfaces, spawns codex app-server automatically)
npm start

# Connect to external app-server
START_APP_SERVER=false CODEX_APP_SERVER_URL=ws://localhost:4500 npm start

# Bind specific interface + custom port
BRIDGE_HOST=0.0.0.0 BRIDGE_PORT=4502 npm start
```

### Client Example

```javascript
const WebSocket = require('ws');

const ws = new WebSocket('ws://127.0.0.1:4501');

ws.on('open', () => {
  console.log('Connected to bridge server');
  
  // Create a session
  ws.send(JSON.stringify({
    jsonrpc: '2.0',
    method: 'session.create',
    id: 1
  }));
});

ws.on('message', (data) => {
  const message = JSON.parse(data.toString());
  console.log('Received:', message);
  
  // Handle session creation
  if (message.method === 'connected') {
    console.log('Client ID:', message.params.clientId);
  }
  
  if (message.result?.sessionId) {
    const sessionId = message.result.sessionId;
    console.log('Session created:', sessionId);
    
    // Send a message to Codex
    ws.send(JSON.stringify({
      jsonrpc: '2.0',
      method: 'send',
      params: {
        sessionId,
        message: {
          jsonrpc: '2.0',
          method: 'generate',
          params: {
            prompt: 'Write a hello world function'
          },
          id: 1
        }
      },
      id: 2
    }));
  }
  
  // Handle streaming responses
  if (message.method === 'stream') {
    console.log('Stream data:', message.params);
  }
});
```

## JSON-RPC API

### Methods

#### `session.create`

Create a new session with Codex app-server.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "method": "session.create",
  "id": 1
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "sessionId": "session-abc123"
  }
}
```

#### `session.close`

Close an existing session.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "method": "session.close",
  "params": {
    "sessionId": "session-abc123"
  },
  "id": 2
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "closed": true,
    "sessionId": "session-abc123"
  }
}
```

#### `send`

Send a message to Codex through a session.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "method": "send",
  "params": {
    "sessionId": "session-abc123",
    "message": {
      "jsonrpc": "2.0",
      "method": "generate",
      "params": {
        "prompt": "Hello, Codex!"
      },
      "id": 1
    }
  },
  "id": 3
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "sent": true,
    "sessionId": "session-abc123",
    "messageId": 42
  }
}
```

#### `stream`

Check streaming status for a session.

**Request:**
```json
{
  "jsonrpc": "2.0",
  "method": "stream",
  "params": {
    "sessionId": "session-abc123"
  },
  "id": 4
}
```

**Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "streaming": true,
    "sessionId": "session-abc123",
    "status": "active"
  }
}
```

### Server Notifications

#### `connected`

Sent when a client connects.

```json
{
  "jsonrpc": "2.0",
  "method": "connected",
  "params": {
    "clientId": "msg-1234567890-abc123",
    "serverVersion": "1.0.0"
  }
}
```

#### `stream`

Streaming data from Codex.

```json
{
  "jsonrpc": "2.0",
  "method": "stream",
  "params": {
    "sessionId": "session-abc123",
    "result": { ... }
  }
}
```

#### `shutdown`

Sent when server is shutting down.

```json
{
  "jsonrpc": "2.0",
  "method": "shutdown",
  "params": {
    "reason": "server_shutdown"
  }
}
```

## Health Check

```bash
curl http://127.0.0.1:4502/health
```

**Response:**
```json
{
  "status": "ok",
  "uptime": 123.456,
  "clients": 2,
  "sessions": 1,
  "port": 4501,
  "appServerUrl": "ws://127.0.0.1:4500"
}
```

## Error Codes

| Code | Message | Description |
|------|---------|-------------|
| -32700 | Parse error | Invalid JSON received |
| -32601 | Method not found | Unknown method requested |
| -32602 | Invalid params | Missing or invalid parameters |
| -32001 | Session creation failed | Failed to create session |
| -32002 | Session not found | Invalid session ID |
| -32003 | Connection unavailable | Session connection lost |

## Reconnect Handling

The bridge server automatically:
- Cleans up sessions when clients disconnect
- Closes app-server connections on session termination
- Handles app-server reconnection on new session creation

For client reconnection:
1. Reconnect to bridge server
2. Create a new session with `session.create`
3. Resume operations with new session ID

## Graceful Shutdown

The server handles `SIGINT` and `SIGTERM` signals:
1. Notifies all connected clients
2. Closes all active sessions
3. Terminates app-server process (if spawned)
4. Exits cleanly

## Development

```bash
# Run with auto-reload
npm run dev

# Custom environment
BRIDGE_PORT=4502 START_APP_SERVER=false npm start
```

## License

ISC
