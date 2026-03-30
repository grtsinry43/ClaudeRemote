import {
  query,
  listSessions,
  getSessionMessages,
  getSessionInfo,
} from '@anthropic-ai/claude-agent-sdk';
import { randomUUID } from 'crypto';
import type { Approval } from './types.js';

interface ApprovalResolver {
  resolve: (result: { behavior: 'allow' | 'deny'; updatedInput?: Record<string, unknown>; message?: string }) => void;
}

interface ActiveQuery {
  sessionId: string;
  abortController: AbortController;
}

export class SessionManager {
  private activeQueries = new Map<string, ActiveQuery>();
  private approvals = new Map<string, Approval & { resolver: ApprovalResolver }>();
  private listeners = new Map<string, Set<(event: string, data: unknown) => void>>();

  // ─── Sessions (all from Agent SDK) ────────────────────

  async getSessions(dir?: string) {
    const sessions = await listSessions(
      dir ? { dir } : undefined,
    );

    return sessions.map((s) => ({
      sessionId: s.sessionId,
      summary: s.summary,
      lastModified: s.lastModified,
      customTitle: s.customTitle,
      firstPrompt: s.firstPrompt,
      gitBranch: s.gitBranch,
      cwd: s.cwd,
      createdAt: s.createdAt,
      isActive: this.activeQueries.has(s.sessionId),
    }));
  }

  async getMessages(
    sessionId: string,
    options?: { dir?: string; limit?: number; offset?: number },
  ) {
    const messages = await getSessionMessages(sessionId, {
      dir: options?.dir,
      limit: options?.limit,
      offset: options?.offset,
    });

    return messages.map((m) => ({
      type: m.type,
      uuid: m.uuid,
      sessionId: m.session_id,
      message: m.message,
    }));
  }

  // ─── Send message (new or resume) ─────────────────────

  async sendMessage(
    prompt: string,
    options: { sessionId?: string; cwd?: string },
  ): Promise<void> {
    const abortController = new AbortController();
    let resolvedSessionId = options.sessionId ?? 'pending';

    // When resuming, look up the session's original cwd
    let cwd = options.cwd ?? process.cwd();
    if (options.sessionId) {
      try {
        const info = await getSessionInfo(options.sessionId);
        if (info?.cwd) {
          cwd = info.cwd;
        }
      } catch {
        // fall back to provided or process cwd
      }
    }

    const queryOptions: Record<string, unknown> = {
      abortController,
      includePartialMessages: true,
      cwd,
      permissionMode: 'default' as const,
    };

    if (options.sessionId) {
      queryOptions['resume'] = options.sessionId;
    }

    // Permission callback: pause and wait for mobile approval.
    queryOptions['canUseTool'] = async (
      toolName: string,
      input: Record<string, unknown>,
      _opts: unknown,
    ) => {
      return this.requestApproval(resolvedSessionId, toolName, input);
    };

    if (options.sessionId) {
      this.activeQueries.set(options.sessionId, {
        sessionId: options.sessionId,
        abortController,
      });
    }

    this.emit(resolvedSessionId, 'status_update', {
      sessionId: resolvedSessionId,
      isActive: true,
    });

    try {
      const q = query({
        prompt,
        options: queryOptions as Parameters<typeof query>[0]['options'],
      });

      for await (const message of q) {
        // Init message — capture session ID
        if (message.type === 'system' && 'subtype' in message && message.subtype === 'init') {
          const initMsg = message as { session_id: string; [key: string]: unknown };
          resolvedSessionId = initMsg.session_id;
          this.activeQueries.set(resolvedSessionId, {
            sessionId: resolvedSessionId,
            abortController,
          });
          this.emit(resolvedSessionId, 'session_init', {
            sessionId: resolvedSessionId,
          });
        }

        // Streaming partial messages
        if (message.type === 'stream_event') {
          const streamMsg = message as { event: unknown; [key: string]: unknown };
          this.emit(resolvedSessionId, 'stream_event', {
            sessionId: resolvedSessionId,
            event: streamMsg.event,
          });
        }

        // Final result
        if (message.type === 'result') {
          const resultMsg = message as {
            subtype: string;
            result?: string;
            session_id: string;
            total_cost_usd: number;
            num_turns: number;
            [key: string]: unknown;
          };
          resolvedSessionId = resultMsg.session_id;
          this.emit(resolvedSessionId, 'message', {
            sessionId: resolvedSessionId,
            subtype: resultMsg.subtype,
            result: resultMsg.result ?? null,
            totalCostUsd: resultMsg.total_cost_usd,
            numTurns: resultMsg.num_turns,
          });
        }
      }
    } catch (err) {
      const error = err as Error;
      console.error(`[session ${resolvedSessionId}] query error:`, error.message);
      if (error.name !== 'AbortError') {
        this.emit(resolvedSessionId, 'error', {
          sessionId: resolvedSessionId,
          error: error.message,
          stack: error.stack,
        });
      }
    } finally {
      this.activeQueries.delete(resolvedSessionId);
      this.emit(resolvedSessionId, 'status_update', {
        sessionId: resolvedSessionId,
        isActive: false,
      });
    }
  }

  // ─── Approvals ────────────────────────────────────────

  getPendingApprovals(): Approval[] {
    return Array.from(this.approvals.values())
      .filter((a) => a.status === 'pending')
      .map(({ resolver: _, ...approval }) => approval);
  }

  private requestApproval(
    sessionId: string,
    toolName: string,
    toolInput: Record<string, unknown>,
  ): Promise<{ behavior: 'allow' | 'deny'; updatedInput?: Record<string, unknown>; message?: string }> {
    const kind = toolName === 'AskUserQuestion' ? 'ask_user' : 'tool_approval';

    return new Promise((resolve) => {
      const id = randomUUID();
      const approval: Approval & { resolver: ApprovalResolver } = {
        id,
        sessionId,
        toolName,
        toolInput,
        kind,
        description: kind === 'ask_user'
          ? 'Claude is asking a question'
          : `${toolName}: ${JSON.stringify(toolInput).slice(0, 200)}`,
        status: 'pending',
        createdAt: new Date().toISOString(),
        resolver: { resolve },
      };
      this.approvals.set(id, approval);
      this.emit(sessionId, 'approval_request', {
        id,
        sessionId,
        kind,
        toolName,
        toolInput,
        description: approval.description,
        createdAt: approval.createdAt,
      });
    });
  }

  /**
   * Respond to an approval request.
   * For tool_approval: allowed=true/false
   * For ask_user: allowed=true with answers object
   */
  respondToApproval(
    approvalId: string,
    allowed: boolean,
    answers?: Record<string, string>,
  ): boolean {
    const approval = this.approvals.get(approvalId);
    if (!approval || approval.status !== 'pending') return false;

    approval.status = allowed ? 'approved' : 'denied';

    if (!allowed) {
      approval.resolver.resolve({
        behavior: 'deny',
        message: 'Denied by user via Claude Remote',
      });
    } else if (approval.kind === 'ask_user' && answers) {
      // AskUserQuestion: return answers in updatedInput
      approval.resolver.resolve({
        behavior: 'allow',
        updatedInput: {
          questions: approval.toolInput['questions'],
          answers,
        },
      });
    } else {
      approval.resolver.resolve({
        behavior: 'allow',
        updatedInput: approval.toolInput,
      });
    }

    this.approvals.delete(approvalId);
    return true;
  }

  // ─── Stop ─────────────────────────────────────────────

  stopSession(sessionId: string): boolean {
    const active = this.activeQueries.get(sessionId);
    if (!active) return false;
    active.abortController.abort();
    return true;
  }

  // ─── Event system ─────────────────────────────────────

  subscribe(key: string, listener: (event: string, data: unknown) => void) {
    if (!this.listeners.has(key)) {
      this.listeners.set(key, new Set());
    }
    this.listeners.get(key)!.add(listener);
    return () => {
      this.listeners.get(key)?.delete(listener);
    };
  }

  private emit(sessionId: string, event: string, data: unknown) {
    this.listeners.get(sessionId)?.forEach((fn) => fn(event, data));
    this.listeners.get('*')?.forEach((fn) => fn(event, data));
  }
}
