# CodexDroid Bridge Server

Lightweight WebSocket proxy server that wraps `codex app-server` and exposes it to clients over WebSocket with JSON-RPC interface.

## Features

- **Session Management**: Create, manage, and close sessions with Codex app-server
- **Real-time Streaming**: Stream Codex responses back to clients instantly
- **JSON-RPC 2.0**: Clean protocol for all operations
- **Debug Logging**: Configurable verbose logging for troubleshooting
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
| `LOG_LEVEL` | `info` | Logging level: `debug`, `info`, `warn`, `error` |
| `BRIDGE_DEBUG` | unset | Set to `1` to enable debug logging (shortcut for `LOG_LEVEL=debug`) |
| `SESSION_CREATE_TIMEOUT_MS` | `5000` | Timeout for session creation and app-server connection |
| `RPC_PING_ENDPOINT` | `/rpc-ping` | HTTP endpoint to test app-server connectivity |

## Usage

### Start the Server

```bash
# Default (bind all interfaces, spawns codex app-server automatically)
npm start

# Enable debug logging
LOG_LEVEL=debug npm start

# Or use the shortcut
BRIDGE_DEBUG=1 npm start

# Connect to external app-server
START_APP_SERVER=false CODEX_APP_SERVER_URL=ws://localhost:4500 npm start

# Bind specific interface + custom port
BRIDGE_HOST=0.0.0.0 BRIDGE_PORT=4502 npm start
```

### Debug Logging


### RPC Ping Endpoint

Test connectivity to the Codex app-server with the built-in HTTP ping endpoint:

```bash
# Quick health check
curl http://127.0.0.1:4502/rpc-ping

# Sample response (success)
{
  "status": "ok",
  "appServer": "connected",
  "latencyMs": 45,
  "timestamp": "2026-02-28T10:30:00.000Z"
}

# Sample response (app-server unavailable)
{
  "status": "error",
  "appServer": "disconnected",
  "latencyMs": 5023,
  "error": "Connection timeout to ws://127.0.0.1:4500 after 5000ms",
  "timestamp": "2026-02-28T10:30:05.000Z"
}
```

This endpoint:
1. Connects to the configured `CODEX_APP_SERVER_URL`
2. Sends a JSON-RPC `ping` request
3. Measures round-trip latency
4. Returns status and timing information

Useful for:
- Health checks in orchestration systems
- Monitoring app-server availability
- Debugging connection issues

Set `LOG_LEVEL=debug` or `BRIDGE_DEBUG=1` to enable verbose logging:

```bash
LOG_LEVEL=debug npm start
```

**Sample debug output:**
```
[10:15:32][bridge][info] CodexDroid Bridge Server v1.0.0 starting
[10:15:32][bridge][info] Configuration: PORT=4501, HOST=0.0.0.0, APP_SERVER=ws://127.0.0.1:4500, START_APP_SERVER=true
[10:15:32][bridge][info] Log level: debug (set LOG_LEVEL=debug for verbose logging)
[10:15:32][bridge][info] Starting codex app-server...
[10:15:34][bridge][info] Bridge server listening on ws://0.0.0.0:4501
[10:15:35][bridge][info] Client connected: msg-1709117735-abc123
[10:15:35][bridge][debug] WebSocket connection opened from 127.0.0.1:52341
[10:15:35][bridge][debug] Client msg-1709117735-abc123 request: session.create (id: 1)
[10:15:35][bridge][debug] Creating session for client msg-1709117735-abc123
[10:15:35][bridge][debug] Connecting to app-server at ws://127.0.0.1:4500...
[10:15:35][bridge][debug] Connected to app-server
[10:15:35][bridge][info] Session created: session-a1b2c3d4 for client msg-1709117735-abc123
[10:15:35][bridge][debug] session.create succeeded: session-a1b2c3d4
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

**Error Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32001,
    "message": "Failed to create session: Connection timeout to ws://127.0.0.1:4500",
    "details": "Error: Connection timeout..."
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
| -32001 | Session creation failed | Failed to create session (app-server unavailable, timeout, etc.) |
| -32002 | Session not found | Invalid session ID |
| -32003 | Connection unavailable | Session connection lost |

## Troubleshooting

### Session Creation Timeout

**Symptom:** Client receives error: `Failed to create session: Connection timeout to ws://127.0.0.1:4500`

**Quick Fixes:**

1. **Check if Codex is installed and logged in:**
   ```bash
   # Verify codex CLI is available
   codex --version
   
   # Ensure you're authenticated
   codex auth status
   
   # If not logged in, authenticate first
   codex auth login
   ```

2. **Test app-server manually:**
   ```bash
   # Start app-server in one terminal
   codex app-server --listen ws://127.0.0.1:4500
   
   # In another terminal, verify it's running
   curl http://127.0.0.1:4502/rpc-ping
   ```

3. **Enable debug logging on bridge server:**
   ```bash
   # Run bridge with verbose output
   LOG_LEVEL=debug npm start
   
   # Or use the shortcut
   BRIDGE_DEBUG=1 npm start
   ```
   
   **What to look for in logs:**
   ```
   [10:15:35][bridge][debug] Connecting to app-server at ws://127.0.0.1:4500...
   [10:15:35][bridge][debug] Connected to app-server
   [10:15:35][bridge][info] Session created: session-a1b2c3d4
   ```
   
   **If connection fails, you'll see:**
   ```
   [10:15:35][bridge][error] Failed to connect to app-server: ECONNREFUSED
   [10:15:35][bridge][error] session.create failed: Connection timeout after 5000ms
   ```

4. **Use the /rpc-ping endpoint:**
   ```bash
   # Quick connectivity test
   curl http://127.0.0.1:4502/rpc-ping
   
   # Success response
   {"status":"ok","appServer":"connected","latencyMs":45}
   
   # Failure response
   {"status":"error","appServer":"disconnected","error":"Connection timeout..."}
   ```

5. **Check configuration:**
   ```bash
   # Verify bridge is pointing to correct app-server URL
   echo $CODEX_APP_SERVER_URL
   # Should be: ws://127.0.0.1:4500 (or your custom URL)
   
   # If app-server runs on different port, update:
   CODEX_APP_SERVER_URL=ws://127.0.0.1:9999 npm start
   ```

6. **Adjust timeout if needed:**
   ```bash
   # Increase session creation timeout (default: 5000ms)
   SESSION_CREATE_TIMEOUT_MS=10000 npm start
   ```

**Common Causes:**
- ❌ Codex CLI not installed → `npm install -g @openai/codex`
- ❌ Not authenticated → `codex auth login`
- ❌ app-server not running → Start with `codex app-server --listen ws://127.0.0.1:4500`
- ❌ Wrong port in `CODEX_APP_SERVER_URL` → Check and update
- ❌ Firewall blocking localhost → Allow connections on 4500/4501/4502

### No Logs Appearing

**Problem:** Bridge server starts but no logs appear, or only errors show.

**Solution:**
```bash
# Default log level is 'info'. Enable debug mode:
LOG_LEVEL=debug npm start

# Or use the shortcut:
BRIDGE_DEBUG=1 npm start

# Verify log level in startup output:
# [10:15:32][bridge][info] Log level: debug
```

**Log Levels:**
| Level | Shows |
|-------|-------|
| `error` | Only errors |
| `warn` | Warnings + errors |
| `info` (default) | Startup, connections, sessions |
| `debug` | All JSON-RPC messages, connection details |

### Client Disconnects Unexpectedly

**Symptom:** Client connects but disconnects shortly after, or during session creation.

**Debug Steps:**

1. **Enable debug logging:**
   ```bash
   LOG_LEVEL=debug npm start
   ```

2. **Check for these log patterns:**
   ```
   [10:15:35][bridge][info] Client connected: msg-1709117735-abc123
   [10:15:35][bridge][debug] WebSocket connection opened from 127.0.0.1:52341
   [10:15:40][bridge][info] Client disconnected: msg-1709117735-abc123
   [10:15:40][bridge][debug] Reason: socket hang up
   ```

3. **Common causes:**
   - Client-side timeout (increase client timeout)
   - Network instability (check localhost connectivity)
   - Invalid WebSocket URL (verify `ws://127.0.0.1:4501`)
   - Bridge server crashed (check for error logs before disconnect)

4. **Test with the included test client:**
   ```bash
   # Start bridge server
   npm start
   
   # In another terminal, run test client
   node test/test-client.js
   ```

### /rpc-ping Returns Error

**Symptom:** `curl http://127.0.0.1:4502/rpc-ping` returns error status.

**Diagnosis:**

```bash
# Test ping endpoint
curl -v http://127.0.0.1:4502/rpc-ping

# If connection refused:
# - Bridge server not running → npm start
# - Wrong port → Check BRIDGE_PORT (health port = BRIDGE_PORT + 1)

# If returns {"status":"error","appServer":"disconnected"}:
# - app-server not running → codex app-server --listen ws://127.0.0.1:4500
# - Wrong URL → Check CODEX_APP_SERVER_URL env var
# - Firewall/port conflict → Verify port 4500 is accessible
```

**Expected Responses:**

✅ **Success:**
```json
{
  "status": "ok",
  "appServer": "connected",
  "latencyMs": 45,
  "timestamp": "2026-02-28T10:30:00.000Z"
}
```

❌ **App-server unavailable:**
```json
{
  "status": "error",
  "appServer": "disconnected",
  "latencyMs": 5023,
  "error": "Connection timeout to ws://127.0.0.1:4500 after 5000ms",
  "timestamp": "2026-02-28T10:30:05.000Z"
}
```

### Codex Authentication Issues

**Symptom:** app-server starts but rejects connections or sessions fail.

**Fix:**

```bash
# Check authentication status
codex auth status

# If not logged in or expired:
codex auth login

# Verify API key is set (if using key-based auth)
echo $OPENAI_API_KEY

# Restart app-server after auth:
codex app-server --listen ws://127.0.0.1:4500
```

### Port Conflicts

**Symptom:** Bridge server fails to start with `EADDRINUSE`.

**Solution:**

```bash
# Check what's using the port
lsof -i :4501  # Bridge WS port
lsof -i :4500  # App-server port
lsof -i :4502  # Health HTTP port

# Kill conflicting process (if safe)
kill -9 <PID>

# Or use different ports:
BRIDGE_PORT=4503 npm start
# Health server will be on 4504 (BRIDGE_PORT + 1)
```

### Quick Diagnostic Script

Save as `diagnose.sh`:

```bash
#!/bin/bash
echo "=== CodexDroid Bridge Diagnostics ==="
echo ""
echo "1. Codex CLI version:"
codex --version 2>/dev/null || echo "   ❌ Codex not installed"
echo ""
echo "2. Auth status:"
codex auth status 2>/dev/null || echo "   ❌ Not authenticated"
echo ""
echo "3. App-server port (4500):"
lsof -i :4500 2>/dev/null || echo "   ❌ Nothing listening"
echo ""
echo "4. Bridge server port (4501):"
lsof -i :4501 2>/dev/null || echo "   ❌ Nothing listening"
echo ""
echo "5. Health endpoint test:"
curl -s http://127.0.0.1:4502/health 2>/dev/null || echo "   ❌ Health endpoint unreachable"
echo ""
echo "6. RPC ping test:"
curl -s http://127.0.0.1:4502/rpc-ping 2>/dev/null || echo "   ❌ RPC ping failed"
echo ""
echo "7. Environment:"
echo "   CODEX_APP_SERVER_URL=$CODEX_APP_SERVER_URL"
echo "   LOG_LEVEL=$LOG_LEVEL"
echo "   BRIDGE_DEBUG=$BRIDGE_DEBUG"
echo "   SESSION_CREATE_TIMEOUT_MS=$SESSION_CREATE_TIMEOUT_MS"
```

Run with: `bash diagnose.sh`

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

# Full debug mode
LOG_LEVEL=debug BRIDGE_DEBUG=1 npm start
```

## Testing

```bash
# Start mock Codex server
node test/mock-codex.js

# Start bridge server with debug logging
LOG_LEVEL=debug BRIDGE_PORT=4501 START_APP_SERVER=false node index.js

# Run test client
node test/test-client.js
```

## License

ISC
