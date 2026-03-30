import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import 'dashboard_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _urlController = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ConnectionProvider>();
    _urlController.text = provider.serverUrl;
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    final provider = context.read<ConnectionProvider>();
    final url = _urlController.text.trim();

    final success = await provider.connect(url);

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      setState(() {
        _connecting = false;
        _error = '无法连接到服务器，请检查地址和后端是否运行';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Claude Remote',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '连接到运行 Claude Code 的桌面端',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'http://192.168.1.x:3200',
                    prefixIcon: const Icon(Icons.link),
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _connect(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _connecting ? null : _connect,
                    child: _connecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('连接'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}
