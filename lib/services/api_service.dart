import 'package:dio/dio.dart';
import '../models/session.dart';
import '../models/approval.dart';

class ApiService {
  late final Dio _dio;
  String _baseUrl;

  ApiService({String baseUrl = 'http://localhost:3200'}) : _baseUrl = baseUrl {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String url, {String token = ''}) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
    if (token.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  // ─── Health ─────────────────────────────────────────

  Future<bool> checkHealth() async {
    try {
      final resp = await _dio.get('/api/health');
      return resp.data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ─── Sessions ───────────────────────────────────────

  Future<List<Session>> getSessions({String? dir}) async {
    final resp = await _dio.get('/api/sessions', queryParameters: {
      if (dir != null) 'dir': dir,
    });
    return (resp.data as List)
        .map((j) => Session.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getSessionMessages(
    String sessionId, {
    String? dir,
    int? limit,
    int? offset,
  }) async {
    final resp = await _dio.get(
      '/api/sessions/$sessionId/messages',
      queryParameters: {
        if (dir != null) 'dir': dir,
        if (limit != null) 'limit': limit.toString(),
        if (offset != null) 'offset': offset.toString(),
      },
    );
    return (resp.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> sendMessage(
    String prompt, {
    String? sessionId,
    String? cwd,
  }) async {
    await _dio.post('/api/sessions/send', data: {
      'prompt': prompt,
      if (sessionId != null) 'sessionId': sessionId,
      if (cwd != null) 'cwd': cwd,
    });
  }

  Future<void> stopSession(String sessionId) async {
    await _dio.delete('/api/sessions/$sessionId');
  }

  // ─── Approvals ──────────────────────────────────────

  Future<List<Approval>> getPendingApprovals() async {
    final resp = await _dio.get('/api/approvals');
    return (resp.data as List)
        .map((j) => Approval.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> respondToApproval(String approvalId, bool allowed) async {
    await _dio.post('/api/approvals/$approvalId', data: {
      'allowed': allowed,
    });
  }
}
