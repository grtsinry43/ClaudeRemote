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
  StreamSubscription? _wsSub;

  ConnectionProvider({required this.api, required this.ws}) {
    _loadSavedUrl();
    _wsSub = ws.connectionState.listen((connected) {
      _isConnected = connected;
      notifyListeners();
    });
  }

  bool get isConnected => _isConnected;
  String get serverUrl => _serverUrl;

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('server_url');
    if (saved != null) {
      _serverUrl = saved;
      api.updateBaseUrl(_serverUrl);
      ws.updateUrl(_serverUrl);
    }
  }

  Future<bool> connect(String url) async {
    _serverUrl = url;
    api.updateBaseUrl(url);
    ws.updateUrl(url);

    final healthy = await api.checkHealth();
    if (healthy) {
      ws.connect();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_url', url);
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
