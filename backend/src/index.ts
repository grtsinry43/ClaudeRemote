import Fastify from 'fastify';
import cors from '@fastify/cors';
import websocket from '@fastify/websocket';
import { SessionManager } from './session-manager.js';
import { FileWatcher } from './file-watcher.js';
import type { WsMessage } from './types.js';

const server = Fastify({ logger: true });
const manager = new SessionManager();

const AUTH_SECRET = process.env['AUTH_SECRET'];
if (!AUTH_SECRET) {
  server.log.warn('AUTH_SECRET not set — running without authentication (local dev only)');
}

// ─── CORS ──────────────────────────────────────────────
const allowedOriginsEnv = process.env['ALLOWED_ORIGINS'];
let corsOrigin: boolean | string[];
if (allowedOriginsEnv) {
  corsOrigin = allowedOriginsEnv.split(',').map((o) => o.trim());
} else if (AUTH_SECRET) {
  corsOrigin = false;
} else {
  corsOrigin = true;
}

await server.register(cors, { origin: corsOrigin });
await server.register(websocket);

// ─── Auth middleware ───────────────────────────────────
if (AUTH_SECRET) {
  server.addHook('onRequest', async (req, reply) => {
    // Skip auth for health check
    if (req.url === '/api/health') return;
    // Skip WebSocket — handled separately in the WS handler
    if (req.headers.upgrade?.toLowerCase() === 'websocket') return;

    const authHeader = req.headers.authorization;
    if (!authHeader || authHeader !== `Bearer ${AUTH_SECRET}`) {
      return reply.status(401).send({ error: 'Unauthorized' });
    }
  });
}

// ─── Helpers ───────────────────────────────────────────
function parsePositiveInt(value: string | undefined): number | undefined {
  if (value === undefined) return undefined;
  const n = parseInt(value, 10);
  if (Number.isNaN(n) || n < 0) return undefined;
  return n;
}

// ─── REST API ───────────────────────────────────────────

server.get('/api/health', async () => ({
  status: 'ok',
  version: '1.0.0',
  timestamp: new Date().toISOString(),
}));

// List all sessions (from Agent SDK — same source as CLI)
server.get<{
  Querystring: { dir?: string };
}>('/api/sessions', async (req) => {
  return manager.getSessions(req.query.dir);
});

// Get messages for a session
server.get<{
  Params: { id: string };
  Querystring: { dir?: string; limit?: string; offset?: string };
}>('/api/sessions/:id/messages', async (req) => {
  return manager.getMessages(req.params.id, {
    dir: req.query.dir,
    limit: parsePositiveInt(req.query.limit),
    offset: parsePositiveInt(req.query.offset),
  });
});

// Send a message (new session or resume existing)
server.post<{
  Body: { prompt: string; sessionId?: string; cwd?: string };
}>('/api/sessions/send', async (req) => {
  const { prompt, sessionId, cwd } = req.body;
  // Fire and forget — errors are pushed via WebSocket
  manager.sendMessage(prompt, { sessionId, cwd }).catch((err) => {
    server.log.error(err, 'sendMessage failed');
  });
  return { status: 'sent' };
});

// Stop an active session
server.delete<{ Params: { id: string } }>('/api/sessions/:id', async (req, reply) => {
  if (manager.stopSession(req.params.id)) {
    return { status: 'stopped' };
  }
  return reply.status(404).send({ error: 'Session not active' });
});

// Approvals
server.get('/api/approvals', async () => manager.getPendingApprovals());

server.post<{
  Params: { id: string };
  Body: { allowed: boolean; answers?: Record<string, string> };
}>('/api/approvals/:id', async (req, reply) => {
  if (manager.respondToApproval(req.params.id, req.body.allowed, req.body.answers)) {
    return { status: 'responded' };
  }
  return reply.status(404).send({ error: 'Approval not found or already handled' });
});

// ─── WebSocket ──────────────────────────────────────────

// Track connected WebSocket clients for push notifications
const wsClients = new Set<import('ws').WebSocket>();

server.register(async (app) => {
  app.get('/ws', { websocket: true }, (socket, req) => {
    // WebSocket authentication via query param
    if (AUTH_SECRET) {
      const url = new URL(req.url ?? '', `http://${req.headers.host}`);
      const token = url.searchParams.get('token');
      if (token !== AUTH_SECRET) {
        socket.close(4001, 'Unauthorized');
        return;
      }
    }

    wsClients.add(socket);

    const unsubscribe = manager.subscribe('*', (event, data) => {
      if (socket.readyState === 1) {
        const msg: WsMessage = { type: event as WsMessage['type'], data };
        socket.send(JSON.stringify(msg));
      }
    });

    socket.on('message', (raw: Buffer) => {
      try {
        const msg = JSON.parse(raw.toString()) as WsMessage;

        if (msg.type === 'send_message') {
          const { prompt, sessionId, cwd } = msg.data as {
            prompt: string;
            sessionId?: string;
            cwd?: string;
          };
          manager.sendMessage(prompt, { sessionId, cwd }).catch((err) => {
            const error = err as Error;
            if (socket.readyState === 1) {
              socket.send(JSON.stringify({
                type: 'error',
                data: { error: error.message },
              }));
            }
          });
        } else if (msg.type === 'approval_response') {
          const { approvalId, allowed, answers } = msg.data as {
            approvalId: string;
            allowed: boolean;
            answers?: Record<string, string>;
          };
          manager.respondToApproval(approvalId, allowed, answers);
        }
      } catch {
        if (socket.readyState === 1) {
          socket.send(JSON.stringify({ type: 'error', data: 'Invalid message' }));
        }
      }
    });

    socket.on('close', () => {
      unsubscribe();
      wsClients.delete(socket);
    });
  });
});

// ─── File Watcher (push session updates on disk changes) ─

function broadcastSessionsUpdate() {
  if (wsClients.size === 0) return;
  manager.getSessions().then((sessions) => {
    const msg = JSON.stringify({
      type: 'sessions_updated',
      data: sessions,
    });
    for (const client of wsClients) {
      if (client.readyState === 1) { // WebSocket.OPEN
        client.send(msg);
      }
    }
  }).catch((err) => {
    server.log.warn(err, 'broadcast getSessions failed');
  });
}

const fileWatcher = new FileWatcher(broadcastSessionsUpdate, 1500);
await fileWatcher.start();

// ─── Start ──────────────────────────────────────────────

const host = process.env['HOST'] ?? '0.0.0.0';
const port = parseInt(process.env['PORT'] ?? '3200', 10);

try {
  await server.listen({ host, port });
  console.log(`Claude Remote backend running at http://${host}:${port}`);
} catch (err) {
  server.log.error(err);
  process.exit(1);
}
