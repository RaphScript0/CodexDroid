const WebSocket = require('ws');
const { spawn } = require('child_process');
const http = require('http');
const crypto = require('crypto');

// Configuration from environment
const BRIDGE_PORT = parseInt(process.env.BRIDGE_PORT, 10) || 4501;
const BRIDGE_HOST = process.env.BRIDGE_HOST || '0.0.0.0';
const CODEX_APP_SERVER_URL = process.env.CODEX_APP_SERVER_URL || 'ws://127.0.0.1:4500';
const START_APP_SERVER = process.env.START_APP_SERVER !== 'false';

// State
const clients = new Map(); // clientId -> WebSocket
const sessions = new Map(); // sessionId -> { clientId, codexWs }
let codexAppServerProcess = null;
let nextMessageId = 1;

// Generate unique IDs
function generateId() {
  return `msg-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

function generateSessionId() {
  return `session-${crypto.randomUUID().substr(0, 8)}`;
}

/**
 * Start Codex app-server as a child process
 */
function startAppServer() {
  if (!START_APP_SERVER) {
    console.log('[bridge] App-server spawning disabled (START_APP_SERVER=false)');
    return Promise.resolve();
  }

  console.log('[bridge] Starting codex app-server...');
  
  return new Promise((resolve, reject) => {
    codexAppServerProcess = spawn('codex', ['app-server', '--listen', CODEX_APP_SERVER_URL], {
      stdio: ['pipe', 'pipe', 'pipe']
    });

    codexAppServerProcess.stdout.on('data', (data) => {
      console.log(`[codex] ${data.toString().trim()}`);
    });

    codexAppServerProcess.stderr.on('data', (data) => {
      const output = data.toString().trim();
      console.error(`[codex] ${output}`);
      
      // Detect when app-server is ready
      if (output.includes('listening') || output.includes('ready')) {
        setTimeout(resolve, 500);
      }
    });

    codexAppServerProcess.on('error', (error) => {
      console.error(`[bridge] Failed to spawn app-server: ${error.message}`);
      console.log('[bridge] Will connect to external app-server instead');
      resolve(); // Continue anyway
    });

    codexAppServerProcess.on('close', (code) => {
      console.log(`[codex] Process exited with code ${code}`);
      codexAppServerProcess = null;
    });

    // Timeout - assume it's starting
    setTimeout(resolve, 2000);
  });
}

/**
 * Connect to Codex app-server WebSocket
 */
function connectToAppServer() {
  return new Promise((resolve, reject) => {
    console.log(`[bridge] Connecting to app-server at ${CODEX_APP_SERVER_URL}...`);
    
    const ws = new WebSocket(CODEX_APP_SERVER_URL);
    
    const timeout = setTimeout(() => {
      if (ws.readyState === WebSocket.CONNECTING) {
        ws.close();
        reject(new Error(`Connection timeout to ${CODEX_APP_SERVER_URL}`));
      }
    }, 5000);

    ws.on('open', () => {
      clearTimeout(timeout);
      console.log('[bridge] Connected to app-server');
      resolve(ws);
    });

    ws.on('error', (error) => {
      clearTimeout(timeout);
      reject(error);
    });
  });
}

/**
 * Create a new session for a client
 */
async function createSession(clientId) {
  try {
    const sessionId = generateSessionId();
    const codexWs = await connectToAppServer();
    
    sessions.set(sessionId, {
      clientId,
      codexWs,
      createdAt: Date.now()
    });

    console.log(`[bridge] Session created: ${sessionId} for client ${clientId}`);
    
    // Set up message handler for this session
    codexWs.on('message', (data) => {
      handleCodexMessage(sessionId, data);
    });

    codexWs.on('close', () => {
      console.log(`[bridge] Session ${sessionId} app-server connection closed`);
      sessions.delete(sessionId);
    });

    codexWs.on('error', (error) => {
      console.error(`[bridge] Session ${sessionId} error: ${error.message}`);
    });

    return sessionId;
  } catch (error) {
    console.error(`[bridge] Failed to create session: ${error.message}`);
    throw error;
  }
}

/**
 * Handle messages from Codex app-server
 */
function handleCodexMessage(sessionId, data) {
  const session = sessions.get(sessionId);
  if (!session) {
    console.log(`[bridge] Received message for unknown session: ${sessionId}`);
    return;
  }

  const client = clients.get(session.clientId);
  if (!client || client.readyState !== WebSocket.OPEN) {
    console.log(`[bridge] Client ${session.clientId} not available, dropping message`);
    return;
  }

  try {
    const message = JSON.parse(data.toString());
    console.log(`[bridge] Session ${sessionId}: forwarding from Codex`);
    
    // Forward to client
    client.send(JSON.stringify({
      jsonrpc: '2.0',
      method: 'stream',
      params: {
        sessionId,
        ...message
      }
    }));
  } catch (error) {
    console.error(`[bridge] Error forwarding message: ${error.message}`);
  }
}

/**
 * Close a session
 */
function closeSession(sessionId) {
  const session = sessions.get(sessionId);
  if (session) {
    if (session.codexWs) {
      session.codexWs.close();
    }
    sessions.delete(sessionId);
    console.log(`[bridge] Session closed: ${sessionId}`);
  }
}

/**
 * Handle client JSON-RPC requests
 */
function handleClientRequest(clientId, request) {
  return new Promise((resolve) => {
    const { method, params, id } = request;

    console.log(`[bridge] Client ${clientId} request: ${method}`);

    switch (method) {
      case 'session.create': {
        createSession(clientId)
          .then((sessionId) => {
            resolve({
              jsonrpc: '2.0',
              id,
              result: { sessionId }
            });
          })
          .catch((error) => {
            resolve({
              jsonrpc: '2.0',
              id,
              error: {
                code: -32001,
                message: `Failed to create session: ${error.message}`
              }
            });
          });
        break;
      }

      case 'session.close': {
        const sessionId = params?.sessionId;
        if (!sessionId) {
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32602,
              message: 'Missing sessionId parameter'
            }
          });
        } else {
          closeSession(sessionId);
          resolve({
            jsonrpc: '2.0',
            id,
            result: { closed: true, sessionId }
          });
        }
        break;
      }

      case 'send': {
        const sessionId = params?.sessionId;
        const message = params?.message;
        
        if (!sessionId) {
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32602,
              message: 'Missing sessionId parameter'
            }
          });
          return;
        }

        if (!message) {
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32602,
              message: 'Missing message parameter'
            }
          });
          return;
        }

        const session = sessions.get(sessionId);
        if (!session) {
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32002,
              message: `Session not found: ${sessionId}`
            }
          });
          return;
        }

        if (session.codexWs.readyState !== WebSocket.OPEN) {
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32003,
              message: 'Session connection not available'
            }
          });
          return;
        }

        // Forward to Codex
        const codexMessageId = nextMessageId++;
        session.codexWs.send(JSON.stringify({
          ...message,
          id: codexMessageId
        }));

        resolve({
          jsonrpc: '2.0',
          id,
          result: {
            sent: true,
            sessionId,
            messageId: codexMessageId
          }
        });
        break;
      }

      case 'stream': {
        // For streaming, we just acknowledge - actual streaming happens via session
        const sessionId = params?.sessionId;
        if (!sessionId) {
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32602,
              message: 'Missing sessionId parameter'
            }
          });
          return;
        }

        const session = sessions.get(sessionId);
        if (!session) {
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32002,
              message: `Session not found: ${sessionId}`
            }
          });
          return;
        }

        resolve({
          jsonrpc: '2.0',
          id,
          result: {
            streaming: true,
            sessionId,
            status: 'active'
          }
        });
        break;
      }

      default: {
        resolve({
          jsonrpc: '2.0',
          id,
          error: {
            code: -32601,
            message: `Method not found: ${method}`
          }
        });
      }
    }
  });
}

/**
 * Create WebSocket server for clients
 */
function createServer() {
  const wss = new WebSocket.Server({ port: BRIDGE_PORT, host: BRIDGE_HOST });

  wss.on('connection', (ws, req) => {
    const clientId = generateId();
    clients.set(clientId, ws);
    
    console.log(`[bridge] Client connected: ${clientId} from ${req.socket.remoteAddress}`);

    // Send connection acknowledgment
    ws.send(JSON.stringify({
      jsonrpc: '2.0',
      method: 'connected',
      params: { clientId, serverVersion: '1.0.0' }
    }));

    ws.on('message', async (data) => {
      try {
        const request = JSON.parse(data.toString());
        const response = await handleClientRequest(clientId, request);
        
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify(response));
        }
      } catch (error) {
        console.error(`[bridge] Error handling message: ${error.message}`);
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({
            jsonrpc: '2.0',
            id: null,
            error: {
              code: -32700,
              message: 'Parse error',
              data: error.message
            }
          }));
        }
      }
    });

    ws.on('close', () => {
      console.log(`[bridge] Client disconnected: ${clientId}`);
      
      // Clean up all sessions for this client
      for (const [sessionId, session] of sessions.entries()) {
        if (session.clientId === clientId) {
          closeSession(sessionId);
        }
      }
      
      clients.delete(clientId);
    });

    ws.on('error', (error) => {
      console.error(`[bridge] Client ${clientId} error: ${error.message}`);
    });

    ws.on('pong', () => {
      // Client is alive
    });
  });

  console.log(`[bridge] Bridge server listening on ws://127.0.0.1:${BRIDGE_PORT}`);
  return wss;
}

/**
 * Health check HTTP server
 */
function createHealthServer() {
  const server = http.createServer((req, res) => {
    if (req.url === '/health') {
      const status = {
        status: 'ok',
        uptime: process.uptime(),
        clients: clients.size,
        sessions: sessions.size,
        port: BRIDGE_PORT,
        appServerUrl: CODEX_APP_SERVER_URL
      };
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(status, null, 2));
    } else if (req.url === '/') {
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('CodexDroid Bridge Server v1.0.0\n');
    } else {
      res.writeHead(404);
      res.end('Not Found\n');
    }
  });

  const healthPort = BRIDGE_PORT + 1;
  server.listen(healthPort, '127.0.0.1', () => {
    console.log(`[bridge] Health server on http://127.0.0.1:${healthPort}`);
  });

  return server;
}

/**
 * Graceful shutdown
 */
function shutdown() {
  console.log('[bridge] Shutting down...');
  
  // Close all client connections
  for (const [clientId, ws] of clients.entries()) {
    ws.send(JSON.stringify({
      jsonrpc: '2.0',
      method: 'shutdown',
      params: { reason: 'server_shutdown' }
    }));
    ws.close(1001, 'Server shutting down');
  }
  
  // Close all sessions
  for (const sessionId of sessions.keys()) {
    closeSession(sessionId);
  }
  
  // Kill app-server process
  if (codexAppServerProcess) {
    codexAppServerProcess.kill('SIGTERM');
  }
  
  console.log('[bridge] Shutdown complete');
  process.exit(0);
}

/**
 * Main entry point
 */
async function main() {
  console.log('╔════════════════════════════════════════╗');
  console.log('║   CodexDroid Bridge Server v1.0.0      ║');
  console.log('╚════════════════════════════════════════╝');
  console.log('');
  console.log('[bridge] Configuration:');
  console.log(`[bridge]   Port: ${BRIDGE_PORT}`);
  console.log(`[bridge]   App-Server: ${CODEX_APP_SERVER_URL}`);
  console.log(`[bridge]   Spawn App-Server: ${START_APP_SERVER}`);
  console.log('');

  // Start app-server if configured
  await startAppServer();

  // Create servers
  const wss = createServer();
  createHealthServer();

  // Handle shutdown signals
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  // Keep alive
  console.log('[bridge] Ready for connections');
}

main().catch((error) => {
  console.error('[bridge] Fatal error:', error);
  process.exit(1);
});
