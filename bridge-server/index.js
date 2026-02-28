const WebSocket = require('ws');
const { spawn } = require('child_process');
const http = require('http');
const crypto = require('crypto');

// Debug logging configuration
const LOG_LEVEL = process.env.LOG_LEVEL || (process.env.BRIDGE_DEBUG ? 'debug' : 'info');
const DEBUG = LOG_LEVEL === 'debug';

function log(level, ...args) {
  const levels = ['debug', 'info', 'warn', 'error'];
  if (levels.indexOf(level) < levels.indexOf(LOG_LEVEL)) return;
  
  const timestamp = new Date().toISOString().split('T')[1].split('.')[0];
  const prefix = `[${timestamp}][bridge][${level}]`;
  
  if (level === 'error') {
    console.error(prefix, ...args);
  } else if (level === 'warn') {
    console.warn(prefix, ...args);
  } else {
    console.log(prefix, ...args);
  }
}

function debug(...args) { log('debug', ...args); }
function info(...args) { log('info', ...args); }
function warn(...args) { log('warn', ...args); }
function error(...args) { log('error', ...args); }

// Configuration from environment
const BRIDGE_PORT = parseInt(process.env.BRIDGE_PORT, 10) || 4501;
const BRIDGE_HOST = process.env.BRIDGE_HOST || '0.0.0.0';
const CODEX_APP_SERVER_URL = process.env.CODEX_APP_SERVER_URL || 'ws://127.0.0.1:4500';
const START_APP_SERVER = process.env.START_APP_SERVER !== 'false';
const SESSION_CREATE_TIMEOUT_MS = parseInt(process.env.SESSION_CREATE_TIMEOUT_MS, 10) || 5000;

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
    info('App-server spawning disabled (START_APP_SERVER=false)');
    return Promise.resolve();
  }

  info('Starting codex app-server...');
  
  return new Promise((resolve, reject) => {
    codexAppServerProcess = spawn('codex', ['app-server', '--listen', CODEX_APP_SERVER_URL], {
      stdio: ['pipe', 'pipe', 'pipe']
    });

    codexAppServerProcess.stdout.on('data', (data) => {
      const output = data.toString().trim();
      if (DEBUG) debug(`codex stdout: ${output}`);
      else info(`codex: ${output}`);
    });

    codexAppServerProcess.stderr.on('data', (data) => {
      const output = data.toString().trim();
      error(`codex stderr: ${output}`);
      
      // Detect when app-server is ready
      if (output.includes('listening') || output.includes('ready')) {
        setTimeout(resolve, 500);
      }
    });

    codexAppServerProcess.on('error', (err) => {
      error(`Failed to spawn app-server: ${err.message}`);
      info('Will connect to external app-server instead');
      resolve(); // Continue anyway
    });

    codexAppServerProcess.on('close', (code) => {
      info(`codex process exited with code ${code}`);
      codexAppServerProcess = null;
    });

    // Timeout - assume it's starting
    setTimeout(resolve, 2000);
  });
}

/**
 * Connect to Codex app-server WebSocket
 */
function connectToAppServer(timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    debug(`Connecting to app-server at ${CODEX_APP_SERVER_URL}...`);
    
    const ws = new WebSocket(CODEX_APP_SERVER_URL);
    
    const timeout = setTimeout(() => {
      if (ws.readyState === WebSocket.CONNECTING) {
        ws.close();
        const msg = `Connection timeout to ${CODEX_APP_SERVER_URL} after ${timeoutMs}ms`;
        error(msg);
        reject(new Error(msg));
      }
    }, timeoutMs);

    ws.on('open', () => {
      clearTimeout(timeout);
      debug('Connected to app-server');
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
    debug(`Creating session for client ${clientId}`);
    const codexWs = await connectToAppServer(SESSION_CREATE_TIMEOUT_MS);
    
    sessions.set(sessionId, {
      clientId,
      codexWs,
      createdAt: Date.now()
    });

    info(`Session created: ${sessionId} for client ${clientId}`);
    
    // Set up message handler for this session
    codexWs.on('message', (data) => {
      handleCodexMessage(sessionId, data);
    });

    codexWs.on('close', () => {
      debug(`Session ${sessionId} app-server connection closed`);
      const session = sessions.get(sessionId);
      if (session) {
        session.codexWs = null; // Mark connection as closed but keep session
      }
    });

    codexWs.on('error', (error) => {
      error(`Session ${sessionId} error: ${err.message}`);
    });

    return sessionId;
  } catch (error) {
    error(`Failed to create session: ${err.message}`);
    throw error;
  }
}

/**
 * Handle messages from Codex app-server
 */
function handleCodexMessage(sessionId, data) {
  const session = sessions.get(sessionId);
  if (!session) {
    warn(`Received message for unknown session: ${sessionId}`);
    return;
  }

  const client = clients.get(session.clientId);
  if (!client || client.readyState !== WebSocket.OPEN) {
    debug(`Client ${session.clientId} not available, dropping message`);
    return;
  }

  try {
    const message = JSON.parse(data.toString());
    debug(`Session ${sessionId}: forwarding from Codex: ${JSON.stringify(message).substring(0, 200)}`);
    
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
    error(`Error forwarding message: ${err.message}`);
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
    info(`Session closed: ${sessionId}`);
  }
}

/**
 * Handle client JSON-RPC requests
 */
function handleClientRequest(clientId, request) {
  return new Promise((resolve) => {
    const { method, params, id } = request;

    debug(`Client ${clientId} request: ${method} (id: ${id})`);
    if (DEBUG) debug(`Request payload: ${JSON.stringify(request).substring(0, 500)}`);

    switch (method) {
      case 'session.create': {
        createSession(clientId)
          .then((sessionId) => {
            debug(`session.create succeeded: ${sessionId}`);
            resolve({
              jsonrpc: '2.0',
              id,
              result: { sessionId }
            });
          })
          .catch((err) => {
            error(`session.create failed: ${err.message}`);
            resolve({
              jsonrpc: '2.0',
              id,
              error: {
                code: -32001,
                message: `Failed to create session: ${err.message}`,
                details: error.stack
              }
            });
          });
        break;
      }

      case 'session.close': {
        const sessionId = params?.sessionId;
        if (!sessionId) {
          warn(`session.close missing sessionId parameter`);
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
          debug(`session.close succeeded: ${sessionId}`);
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
          warn(`send missing sessionId parameter`);
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
          error(`send: session not found: ${sessionId}`);
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32002,
              message: 'Session not found'
            }
          });
          return;
        }

        if (!session.codexWs || session.codexWs.readyState !== WebSocket.OPEN) {
          error(`send: connection unavailable for session ${sessionId}`);
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32003,
              message: 'Connection unavailable'
            }
          });
          return;
        }

        try {
          const msgId = nextMessageId++;
          debug(`Forwarding message to Codex (sessionId: ${sessionId}, msgId: ${msgId})`);
          if (DEBUG) debug(`Message payload: ${JSON.stringify(message).substring(0, 300)}`);
          
          session.codexWs.send(JSON.stringify(message));
          
          resolve({
            jsonrpc: '2.0',
            id,
            result: {
              sent: true,
              sessionId,
              messageId: msgId
            }
          });
        } catch (err) {
          error(`Error sending to Codex: ${err.message}`);
          resolve({
            jsonrpc: '2.0',
            id,
            error: {
              code: -32003,
              message: 'Failed to send message'
            }
          });
        }
        break;
      }

      default:
        warn(`Unknown method: ${method}`);
        resolve({
          jsonrpc: '2.0',
          id,
          error: {
            code: -32601,
            message: `Method not found: ${method}`
          }
        });
    }
  });
}

/**
 * Create WebSocket server for client connections
 */
function createServer() {
  const wss = new WebSocket.Server({
    host: BRIDGE_HOST,
    port: BRIDGE_PORT
  });

  wss.on('connection', (ws) => {
    const clientId = generateId();
    debug(`Client connected: ${clientId}`);
    
    clients.set(clientId, ws);

    ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data.toString());
        debug(`Client ${clientId} message: ${JSON.stringify(message).substring(0, 200)}`);
        
        const response = await handleClientRequest(clientId, message);
        
        debug(`Sending response: ${JSON.stringify(response).substring(0, 300)}`);
        ws.send(JSON.stringify(response));
      } catch (error) {
        error(`Error handling message: ${error.message}`);
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
    });

    ws.on('close', () => {
      debug(`Client disconnected: ${clientId}`);
      clients.delete(clientId);
      
      // Clean up sessions for this client
      const clientSessionIds = [];
      for (const [sessionId, session] of sessions.entries()) {
        if (session.clientId === clientId) {
          clientSessionIds.push(sessionId);
        }
      }
      
      debug(`Cleaning up ${clientSessionIds.length} session(s) for this client`);
      for (const sessionId of clientSessionIds) {
        closeSession(sessionId);
      }
    });

    ws.on('error', (error) => {
      error(`Client ${clientId} error: ${err.message}`);
    });

    info(`Client connected: ${clientId}`);
  });

  info(`Bridge WebSocket server listening on ${BRIDGE_HOST}:${BRIDGE_PORT}`);
  
  return wss;
}

/**
 * Health check HTTP server
 */
function createHealthServer() {
  const healthServer = http.createServer((req, res) => {
    if (req.url === '/health') {
      const startTime = Date.now();
      debug(`Health check request received`);
      
      // Try to connect to app-server to verify it's available
      connectToAppServer(SESSION_CREATE_TIMEOUT_MS)
        .then((ws) => {
          ws.close();
          const totalLatency = Date.now() - startTime;
          debug(`Health check: app-server connected in ${totalLatency}ms`);
          
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            status: 'ok',
            appServer: 'connected',
            latencyMs: totalLatency,
            timestamp: new Date().toISOString()
          }));
        })
        .catch((error) => {
          const latency = Date.now() - startTime;
          debug(`Health check: app-server connection failed: ${error.message}`);
          
          res.writeHead(503, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            status: 'error',
            appServer: 'disconnected',
            latencyMs: latency,
            error: error.message,
            timestamp: new Date().toISOString()
          }));
        });
    } else if (req.url === '/rpc-ping') {
      handleRpcPing(req, res);
    } else {
      res.writeHead(404);
      res.end('Not found');
    }
  });

  const healthPort = BRIDGE_PORT + 1;
  healthServer.listen(healthPort, BRIDGE_HOST, () => {
    info(`Health check server listening on ${BRIDGE_HOST}:${healthPort}`);
  });
}

/**

/**
 * Handle RPC ping request - test connection to app-server
 */
function handleRpcPing(req, res) {
  const startTime = Date.now();
  
  debug(`/rpc-ping: sending JSON-RPC ping to app-server`);
  
  connectToAppServer(SESSION_CREATE_TIMEOUT_MS)
    .then((ws) => {
      const pingPayload = JSON.stringify({
        jsonrpc: '2.0',
        id: 'ping-' + Date.now(),
        method: 'ping',
        params: {}
      });
      
      let responded = false;
      const timeout = setTimeout(() => {
        if (!responded) {
          responded = true;
          ws.close();
          const latency = Date.now() - startTime;
          debug(`/rpc-ping: timeout after ${latency}ms`);
          res.writeHead(504, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            status: 'timeout',
            appServer: 'no-response',
            latencyMs: latency,
            timestamp: new Date().toISOString()
          }));
        }
      }, SESSION_CREATE_TIMEOUT_MS);
      
      ws.on('message', (data) => {
        if (responded) return;
        clearTimeout(timeout);
        responded = true;
        ws.close();
        const latency = Date.now() - startTime;
        debug(`/rpc-ping: received response in ${latency}ms`);
        
        try {
          const response = JSON.parse(data.toString());
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            status: 'ok',
            appServer: 'responded',
            latencyMs: latency,
            rpcResponse: response,
            timestamp: new Date().toISOString()
          }));
        } catch (e) {
          res.writeHead(502, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            status: 'error',
            appServer: 'invalid-response',
            latencyMs: latency,
            error: 'Failed to parse app-server response',
            timestamp: new Date().toISOString()
          }));
        }
      });
      
      ws.on('error', (error) => {
        if (responded) return;
        clearTimeout(timeout);
        responded = true;
        const latency = Date.now() - startTime;
        debug(`/rpc-ping: websocket error: ${error.message}`);
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          status: 'error',
          appServer: 'connection-error',
          latencyMs: latency,
          error: error.message,
          timestamp: new Date().toISOString()
        }));
      });
      
      ws.send(pingPayload);
      debug(`/rpc-ping: sent ping payload`);
    })
    .catch((error) => {
      const latency = Date.now() - startTime;
      debug(`/rpc-ping: failed to connect: ${error.message}`);
      res.writeHead(503, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'error',
        appServer: 'disconnected',
        latencyMs: latency,
        error: error.message,
        timestamp: new Date().toISOString()
      }));
    });
}

/**
 * Graceful shutdown
 */
function shutdown() {
  info('Shutting down...');
  info(`Active clients: ${clients.size}, Active sessions: ${sessions.size}`);
  
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
  
  info('Shutdown complete');
  process.exit(0);
}

/**
 * Main entry point
 */
async function main() {
  info('CodexDroid Bridge Server v1.0.0 starting');
  info(`Configuration: PORT=${BRIDGE_PORT}, HOST=${BRIDGE_HOST}, APP_SERVER=${CODEX_APP_SERVER_URL}, START_APP_SERVER=${START_APP_SERVER}`);
  info(`Log level: ${LOG_LEVEL} (set LOG_LEVEL=debug for verbose logging)`);

  // Start app-server if configured
  await startAppServer();

  // Create servers
  const wss = createServer();
  createHealthServer();

  // Handle shutdown signals
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  // Keep alive
  info('Ready for connections');
}

main().catch((err) => {
  error(`Fatal error: ${err.message}`);
  error(err.stack);
  process.exit(1);
});
