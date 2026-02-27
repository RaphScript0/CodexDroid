const WebSocket = require('ws');

const BRIDGE_URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:4501';

console.log(`[test-client] Connecting to ${BRIDGE_URL}...`);

const ws = new WebSocket(BRIDGE_URL);
let sessionId = null;

ws.on('open', () => {
  console.log('[test-client] ✅ Connected');
});

ws.on('message', (data) => {
  const msg = JSON.parse(data.toString());
  console.log('[test-client] Received:', JSON.stringify(msg, null, 2));

  // Handle connection notification
  if (msg.method === 'connected') {
    console.log('[test-client] Client ID:', msg.params.clientId);
    
    // Create a session
    console.log('[test-client] Creating session...');
    ws.send(JSON.stringify({
      jsonrpc: '2.0',
      method: 'session.create',
      id: 1
    }));
  }

  // Handle session creation
  if (msg.result?.sessionId) {
    sessionId = msg.result.sessionId;
    console.log('[test-client] ✅ Session created:', sessionId);
    
    // Send a message
    console.log('[test-client] Sending message to Codex...');
    ws.send(JSON.stringify({
      jsonrpc: '2.0',
      method: 'send',
      params: {
        sessionId,
        message: {
          jsonrpc: '2.0',
          method: 'generate',
          params: { prompt: 'Hello!' },
          id: 1
        }
      },
      id: 2
    }));
  }

  // Handle streaming responses
  if (msg.method === 'stream') {
    console.log('[test-client] 📡 Stream:', msg.params.result);
  }
});

ws.on('error', (error) => {
  console.error('[test-client] ❌ Error:', error.message);
});

ws.on('close', () => {
  console.log('[test-client] Connection closed');
  process.exit(0);
});

// Close after 5 seconds
setTimeout(() => {
  if (sessionId) {
    console.log('[test-client] Closing session...');
    ws.send(JSON.stringify({
      jsonrpc: '2.0',
      method: 'session.close',
      params: { sessionId },
      id: 3
    }));
  }
  setTimeout(() => ws.close(), 500);
}, 5000);
