const WebSocket = require('ws');

// Mock Codex app-server for testing
const CODEX_PORT = 4500;
const wss = new WebSocket.Server({ port: CODEX_PORT });

console.log(`[mock-codex] Listening on ws://127.0.0.1:${CODEX_PORT}`);

wss.on('connection', (ws) => {
  const sessionId = `codex-${Date.now()}`;
  console.log(`[mock-codex] Session connected: ${sessionId}`);

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      console.log(`[mock-codex] Received: ${JSON.stringify(msg)}`);

      // Simulate streaming response
      const chunks = [
        { type: 'chunk', content: 'Hello' },
        { type: 'chunk', content: ' from' },
        { type: 'chunk', content: ' Codex!' },
        { type: 'done', result: 'Hello from Codex!', final: true }
      ];

      let i = 0;
      const interval = setInterval(() => {
        if (i >= chunks.length) {
          clearInterval(interval);
          // Keep connection open - don't close after sending chunks
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

    } catch (error) {
      console.error(`[mock-codex] Error: ${error.message}`);
    }
  });

  // Connection close handler - keep connection open until client closes
  ws.on('close', () => {
    console.log(`[mock-codex] Session closed: ${sessionId}`);
  });

  ws.on('error', (error) => {
    console.error(`[mock-codex] Session error: ${error.message}`);
  });
});
