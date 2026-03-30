import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WsEvent {
  final String type;
  final dynamic data;
  WsEvent({required this.type, required this.data});
}

class WsService {
  WebSocketChannel? _channel;
  final _eventController = StreamController<WsEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  Timer? _reconnectTimer;
  String _wsUrl = 'ws://localhost:3200/ws';
  bool _shouldReconnect = true;

  Stream<WsEvent> get events => _eventController.stream;
  Stream<bool> get connectionState => _connectionController.stream;

  void updateUrl(String httpUrl, {String token = ''}) {
    final base = '${httpUrl.replaceFirst('http', 'ws').replaceFirst(RegExp(r'/$'), '')}/ws';
    _wsUrl = token.isNotEmpty ? '$base?token=$token' : base;
  }

  void connect() {
    _shouldReconnect = true;
    _doConnect();
  }

  void _doConnect() {
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _connectionController.add(true);

      _channel!.stream.listen(
        (raw) {
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;
            _eventController.add(WsEvent(
              type: json['type'] as String,
              data: json['data'],
            ));
          } catch (_) {}
        },
        onDone: () {
          _connectionController.add(false);
          _scheduleReconnect();
        },
        onError: (_) {
          _connectionController.add(false);
          _scheduleReconnect();
        },
      );
    } catch (_) {
      _connectionController.add(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _doConnect);
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void sendMessage(String sessionId, String message) {
    send({
      'type': 'send_message',
      'data': {'sessionId': sessionId, 'message': message},
    });
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _connectionController.add(false);
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _connectionController.close();
  }
}
