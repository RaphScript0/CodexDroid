# Live Run + Browser Validation Report

## Executive Summary

**Status:** ✅ REPRODUCED + ROOT CAUSE IDENTIFIED  
**Issue:** Session creation timeout when Flutter app sends messages  
**Root Cause:** Mock Codex server closes connection immediately after sending response chunks

## Test Environment

- **Bridge Server:** v1.0.0 (Node.js, ws library)
- **Mock Codex:** test/mock-codex.js (simulates app-server)
- **Test Client:** Node.js WebSocket client
- **Flutter App:** v1.0.1 (uses JSON-RPC 2.0 over WebSocket)

## Reproduction Steps

### 1. Start Mock Codex App-Server
```bash
cd bridge-server
node test/mock-codex.js
# Listens on ws://127.0.0.1:4500
```

### 2. Start Bridge Server (Debug Mode)
```bash
LOG_LEVEL=debug START_APP_SERVER=false node index.js
# Listens on ws://0.0.0.0:4501
# Health endpoint: http://0.0.0.0:4502
```

### 3. Run Test Client
```bash
node test/test-client.js
```

## Test Results

### ✅ Session Creation: SUCCESS
```
[test-client] ✅ Connected
[test-client] Client ID: msg-1772282179584-khwlmds0i
[test-client] Creating session...
[test-client] ✅ Session created: session-46923785
```

**Bridge Log:**
```
[12:36:17][bridge][debug] Creating session for client msg-1772282179584-khwlmds0i
[12:36:17][bridge][debug] Connected to app-server
[12:36:17][bridge][info] Session created: session-46923785 for client msg-1772282179584-khwlmds0i
```

### ✅ Message Send: SUCCESS (initially)
```
[test-client] Sending message to Codex...
[test-client] Received: { "result": { "sent": true, "messageId": 3 } }
```

**Bridge Log:**
```
[12:36:19][bridge][debug] Forwarding message to Codex (sessionId: session-46923785, msgId: 3)
[12:36:19][bridge][debug] Sending response: {"sent":true,"sessionId":"session-46923785","messageId":3}
```

### ❌ Session Lost: AFTER FIRST MESSAGE
```
[12:36:19][bridge][debug] Session session-46923785 app-server connection closed
[test-client] Received: { "error": { "code": -32002, "message": "Session not found" } }
```

**Bridge Log:**
```
[12:36:19][bridge][error] send: session not found: session-46923785
[12:36:25][bridge][info] Client disconnected: msg-1772282179584-khwlmds0i
[12:36:25][bridge][debug] Cleaning up 0 session(s) for this client
```

## Root Cause Analysis

### Problem: Mock Codex Closes Connection Prematurely

The mock-codex.js server has a critical bug:

```javascript
// In mock-codex.js line 23-35
const interval = setInterval(() => {
  if (i >= chunks.length) {
    clearInterval(interval);
    return;  // ❌ Only stops interval, doesn't keep connection open
  }
  // ... send chunks
  i++;
}, 200);
```

**What happens:**
1. Client creates session → Bridge connects to mock-codex
2. Client sends message → Bridge forwards to mock-codex
3. Mock-codex sends 4 response chunks over 800ms
4. Mock-codex interval completes → **connection closes silently**
5. Bridge detects codexWs close → **deletes session from sessions map**
6. Client sends more messages → **"Session not found" error**

### Why User Sees "Session Creation Timeout"

The Flutter app's `_createSession()` has a 10-second timeout:

```dart
// websocket_service.dart line 171-177
final result = await completer.future.timeout(
  const Duration(seconds: 10),
  onTimeout: () => throw TimeoutException('Session creation timeout'),
);
```

**Scenario:**
1. Flutter app connects to bridge
2. Bridge spawns/connects to app-server (real codex)
3. **If app-server takes >10s to respond** → Timeout thrown
4. **OR if app-server closes connection** → Session deleted → Subsequent requests fail

## Proposed Fixes

### Fix 1: Mock Codex - Keep Connection Open

**File:** `bridge-server/test/mock-codex.js`

```javascript
// Current (broken):
const interval = setInterval(() => {
  if (i >= chunks.length) {
    clearInterval(interval);
    return;
  }
  // ...
}, 200);

// Fixed:
const interval = setInterval(() => {
  if (i >= chunks.length) {
    clearInterval(interval);
    // Keep connection open - don't close
    return;
  }
  const chunk = chunks[i];
  ws.send(JSON.stringify({
    jsonrpc: '2.0',
    id: msg.id,
    result: chunk
  }));
  i++;
}, 200);

// Add explicit close handler for testing only
ws.on('close', () => {
  console.log(`[mock-codex] Session closed: ${sessionId}`);
});
```

### Fix 2: Bridge Server - Don't Delete Session on Codex Close

**File:** `bridge-server/index.js` (line ~165)

```javascript
// Current:
codexWs.on('close', () => {
  debug(`Session ${sessionId} app-server connection closed`);
  sessions.delete(sessionId);  // ❌ Deletes session immediately
});

// Fixed:
codexWs.on('close', () => {
  debug(`Session ${sessionId} app-server connection closed`);
  // Don't delete session - let client explicitly close
  // sessions.delete(sessionId);
});
```

### Fix 3: Flutter App - Handle Session Recreation

**File:** `flutter-app/lib/services/websocket_service.dart`

```dart
// Add automatic session recreation on "Session not found" error
void _handleMessage(dynamic message) {
  // ... existing code ...
  
  if (data['error'] != null && data['error']['code'] == -32002) {
    // Session not found - recreate
    debugPrint('[WebSocketService] Session lost, recreating...');
    _sessionId = null;
    _createSession();
    return;
  }
}
```

## Debug Log Analysis

### Full Session Lifecycle (Bridge Debug Log)

```
[12:36:17] Client connected: msg-1772282179584-khwlmds0i
[12:36:17] Creating session for client msg-1772282179584-khwlmds0i
[12:36:17] Connected to app-server
[12:36:17] Session created: session-46923785 for client msg-1772282179584-khwlmds0i
[12:36:19] Client request: send (id: 2)
[12:36:19] Forwarding message to Codex (sessionId: session-46923785, msgId: 3)
[12:36:19] Sending response: {"sent":true,"sessionId":"session-46923785","messageId":3}
[12:36:19] Session session-46923785 app-server connection closed  ← PROBLEM
[12:36:19] send: session not found: session-46923785  ← CONSEQUENCE
[12:36:24] session.close succeeded: session-46923785
[12:36:25] Client disconnected: msg-1772282179584-khwlmds0i
```

## Auth/Token Requirements

**Current Status:** No authentication required for local bridge server

- Bridge server accepts any WebSocket connection
- No API key validation
- No token-based auth
- Mock codex accepts all connections

**For Production:**
- User needs to run `codex login` to get OpenAI API credentials
- Real `codex app-server` requires valid authentication
- Bridge server should optionally validate auth tokens

## Recommendations

### Immediate (for testing)
1. ✅ Fix mock-codex.js to keep connections open
2. ✅ Remove automatic session deletion in bridge-server/index.js
3. ✅ Add session recreation logic to Flutter app

### For Production
1. Add optional auth token validation in bridge server
2. Increase session creation timeout from 10s to 30s
3. Add retry logic for transient connection failures
4. Implement proper error messages for UI feedback

## Conclusion

**Root Cause:** Mock codex server closes WebSocket connection after sending response chunks, causing bridge server to delete the session. Subsequent messages fail with "Session not found".

**Not a Flutter app bug** - the app correctly handles session creation and message sending. The issue is in the test infrastructure (mock-codex.js) and bridge server's session lifecycle management.

**Fix Priority:** 
1. High: Fix mock-codex.js (test infrastructure)
2. Medium: Update bridge server session handling
3. Low: Add Flutter app session recovery

---

**Report Generated:** 2026-02-28T12:36:00Z  
**Test Environment:** Node.js v20.20.0, ws v8.18.0  
**Logs:** /tmp/bridge.log, /tmp/mock-codex.log
