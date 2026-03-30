import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/ws_service.dart';
import 'providers/connection_provider.dart';
import 'providers/session_provider.dart';
import 'screens/connect_screen.dart';

void main() {
  runApp(const ClaudeRemoteApp());
}

class ClaudeRemoteApp extends StatefulWidget {
  const ClaudeRemoteApp({super.key});

  @override
  State<ClaudeRemoteApp> createState() => _ClaudeRemoteAppState();
}

class _ClaudeRemoteAppState extends State<ClaudeRemoteApp> {
  late final ApiService _api;
  late final WsService _ws;

  @override
  void initState() {
    super.initState();
    _api = ApiService();
    _ws = WsService();
  }

  @override
  void dispose() {
    _ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: _api),
        ChangeNotifierProvider(
          create: (_) => ConnectionProvider(api: _api, ws: _ws),
        ),
        ChangeNotifierProvider(
          create: (_) => SessionProvider(api: _api, ws: _ws),
        ),
      ],
      child: MaterialApp(
        title: 'Claude Remote',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD97706), // amber
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD97706),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const ConnectScreen(),
      ),
    );
  }
}
