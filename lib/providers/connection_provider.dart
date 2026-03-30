import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/ws_service.dart';

class ConnectionProvider extends ChangeNotifier {
  final ApiService api;
  final WsService ws;

  bool _isConnected = false;
  String _serverUrl = 'http://localhost:3200';
  String _token = '';
  StreamSubscription? _wsSub;

  ConnectionProvider({required this.api, required this.ws}) {
    _loadSaved();
    _wsSub = ws.connectionState.listen((connected) {
      _isConnected = connected;
      notifyListeners();
    });
  }

  bool get isConnected => _isConnected;
  String get serverUrl => _serverUrl;
  String get token => _token;

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_url');
    final savedToken = prefs.getString('auth_token');
    if (savedUrl != null) {
      _serverUrl = savedUrl;
      _token = savedToken ?? '';
      api.updateBaseUrl(_serverUrl, token: _token);
      ws.updateUrl(_serverUrl, token: _token);
    }
  }

  Future<bool> connect(String url, {String token = ''}) async {
    _serverUrl = url;
    _token = token;
    api.updateBaseUrl(url, token: token);
    ws.updateUrl(url, token: token);

    final healthy = await api.checkHealth();
    if (healthy) {
      ws.connect();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', url);
      await prefs.setString('auth_token', token);
      notifyListeners();
      return true;
    }
    return false;
  }

  void disconnect() {
    ws.disconnect();
    _isConnected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}
