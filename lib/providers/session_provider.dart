import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/session.dart';
import '../models/approval.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';

class SessionProvider extends ChangeNotifier {
  final ApiService api;
  final WsService ws;

  List<Session> _sessions = [];
  final Map<String, String> _streamingTexts = {};
  Timer? _pollTimer;
  StreamSubscription? _wsSub;

  /// Broadcasts sessionId whenever that session has new messages to reload.
  final _messageUpdateController = StreamController<String>.broadcast();
  Stream<String> get messageUpdates => _messageUpdateController.stream;

  /// Broadcasts approval requests so session detail can show bottom sheet.
  final _approvalController = StreamController<Approval>.broadcast();
  Stream<Approval> get approvalRequests => _approvalController.stream;

  /// Broadcasts error messages from the backend.
  final _errorController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get errors => _errorController.stream;

  SessionProvider({required this.api, required this.ws}) {
    _wsSub = ws.events.listen(_handleWsEvent);
  }

  List<Session> get sessions => _sessions;

  String getStreamingText(String sessionId) =>
      _streamingTexts[sessionId] ?? '';

  Future<void> loadSessions() async {
    try {
      _sessions = await api.getSessions();
      notifyListeners();
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadMessages(String sessionId) {
    return api.getSessionMessages(sessionId);
  }

  Future<void> sendMessage(
    String prompt, {
    String? sessionId,
    String? cwd,
  }) async {
    if (sessionId != null) {
      _streamingTexts[sessionId] = '';
    }
    await api.sendMessage(prompt, sessionId: sessionId, cwd: cwd);
  }

  Future<void> stopSession(String sessionId) async {
    await api.stopSession(sessionId);
    await loadSessions();
  }

  void respondToApproval(String approvalId, bool allowed,
      {Map<String, String>? answers}) {
    ws.send({
      'type': 'approval_response',
      'data': {
        'approvalId': approvalId,
        'allowed': allowed,
        if (answers != null) 'answers': answers,
      },
    });
  }

  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      loadSessions();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
  }

  void _handleWsEvent(WsEvent event) {
    switch (event.type) {
      case 'stream_event':
        final data = event.data as Map<String, dynamic>;
        final sessionId = data['sessionId'] as String?;
        final rawEvent = data['event'] as Map<String, dynamic>?;
        if (sessionId != null && rawEvent != null) {
          final type = rawEvent['type'] as String?;
          if (type == 'content_block_delta') {
            final delta = rawEvent['delta'] as Map<String, dynamic>?;
            if (delta?['type'] == 'text_delta') {
              final text = delta!['text'] as String? ?? '';
              _streamingTexts[sessionId] =
                  (_streamingTexts[sessionId] ?? '') + text;
              notifyListeners();
            }
          }
        }
        break;

      case 'message':
        final data = event.data as Map<String, dynamic>;
        final sessionId = data['sessionId'] as String?;
        if (sessionId != null) {
          _streamingTexts[sessionId] = '';
          _messageUpdateController.add(sessionId);
          notifyListeners();
          loadSessions();
        }
        break;

      case 'approval_request':
        final data = event.data as Map<String, dynamic>;
        final approval =
            Approval.fromJson({...data, 'status': 'pending'});
        _approvalController.add(approval);
        break;

      case 'error':
        final data = event.data as Map<String, dynamic>;
        _errorController.add(data);
        // Also clear streaming text for this session
        final errSessionId = data['sessionId'] as String?;
        if (errSessionId != null) {
          _streamingTexts[errSessionId] = '';
        }
        notifyListeners();
        break;

      case 'sessions_updated':
        final data = event.data;
        if (data is List) {
          _sessions = data
              .map((j) => Session.fromJson(j as Map<String, dynamic>))
              .toList();
          notifyListeners();
        }
        break;

      case 'status_update':
      case 'session_init':
        loadSessions();
        break;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wsSub?.cancel();
    _messageUpdateController.close();
    _approvalController.close();
    _errorController.close();
    super.dispose();
  }
}
