export interface Approval {
  id: string;
  sessionId: string;
  toolName: string;
  toolInput: Record<string, unknown>;
  description: string;
  /** 'tool_approval' for permission requests, 'ask_user' for AskUserQuestion */
  kind: 'tool_approval' | 'ask_user';
  status: 'pending' | 'approved' | 'denied';
  createdAt: string;
}

export interface WsMessage {
  type:
    | 'message'
    | 'approval_request'
    | 'approval_response'
    | 'status_update'
    | 'stream_event'
    | 'session_init'
    | 'sessions_updated'
    | 'error'
    | 'send_message';
  data: unknown;
}
