const WebSocket = require('ws');

const BRIDGE_URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:4501';

console.log(`[test-client] Connecting to ${BRIDGE_URL}...`);

const ws = new WebSocket(BRIDGE_URL);
let sessionId = null;
let messageSent = false;
let closeRequested = false;

ws.on('open', () => {
  console.log('[test-client] ✅ Connected');
  
  // Create a session
  console.log('[test-client] Creating session...');
  ws.send(JSON.stringify({
    jsonrpc: '2.0',
    method: 'session.create',
    id: 1
  }));
});

ws.on('message', (data) => {
  const msg = JSON.parse(data.toString());
  
  // Handle session creation response
  if (msg.result?.sessionId && !sessionId) {
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
    messageSent = true;
  }

  // Handle send response
  if (msg.result?.sent && messageSent) {
    console.log('[test-client] ✅ Message sent successfully (messageId:', msg.result.messageId + ')');
  }
  
  // Handle streaming responses
  if (msg.method === 'stream') {
    const result = msg.params.result;
    if (result.type === 'chunk') {
      console.log('[test-client] 📡 Chunk:', result.content);
    } else if (result.type === 'done') {
      console.log('[test-client] 🏁 Done:', result.result);
      
      // Close session after receiving complete response
      if (!closeRequested && sessionId) {
        closeRequested = true;
        console.log('[test-client] Closing session...');
        ws.send(JSON.stringify({
          jsonrpc: '2.0',
          method: 'session.close',
          params: { sessionId },
          id: 3
        }));
        setTimeout(() => ws.close(), 500);
      }
    }
  }
  
  // Handle session close response
  if (msg.result?.closed) {
    console.log('[test-client] ✅ Session closed');
    setTimeout(() => ws.close(), 200);
  }
});

ws.on('error', (error) => {
  console.error('[test-client] ❌ Error:', error.message);
});

ws.on('close', () => {
  console.log('[test-client] Connection closed');
  process.exit(0);
});

// Timeout after 10 seconds
setTimeout(() => {
  console.log('[test-client] ⏰ Timeout - closing');
  ws.close();
}, 10000);
