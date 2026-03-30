import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import 'connect_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conn = context.watch<ConnectionProvider>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Connection status
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('连接状态',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      conn.isConnected
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      color: conn.isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(conn.isConnected ? '已连接' : '未连接'),
                          Text(
                            conn.serverUrl,
                            style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (conn.token.isNotEmpty)
                            Text(
                              '令牌: ${'*' * 8}',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      conn.disconnect();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const ConnectScreen(),
                        ),
                      );
                    },
                    child: const Text('断开并重新连接'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // About
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('关于',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.terminal),
                  title: Text('Claude Remote'),
                  subtitle: Text('Claude Code 远程控制器 v1.0.0'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
