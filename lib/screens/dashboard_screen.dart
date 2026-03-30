import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import '../providers/session_provider.dart';
import '../widgets/unified_session_card.dart';
import 'session_detail_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    context.read<SessionProvider>()
      ..loadSessions()
      ..startPolling();
  }

  @override
  void dispose() {
    context.read<SessionProvider>().stopPolling();
    super.dispose();
  }

  void _newSession() {
    final promptController = TextEditingController();
    final cwdController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建会话'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: promptController,
              decoration: const InputDecoration(
                labelText: '初始提示词',
                hintText: '例如：帮我修复登录 bug',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cwdController,
              decoration: const InputDecoration(
                labelText: '工作目录（可选）',
                hintText: '/path/to/project',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (promptController.text.trim().isEmpty) return;
              final provider = ctx.read<SessionProvider>();
              await provider.sendMessage(
                promptController.text.trim(),
                cwd: cwdController.text.isNotEmpty
                    ? cwdController.text.trim()
                    : null,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _SessionsPage(onNewSession: _newSession),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Claude Remote'),
        actions: [
          Consumer<ConnectionProvider>(
            builder: (_, conn, child) => Icon(
              conn.isConnected ? Icons.cloud_done : Icons.cloud_off,
              color: conn.isConnected ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: pages[_currentIndex],
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _newSession,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: '会话',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class _SessionsPage extends StatelessWidget {
  final VoidCallback onNewSession;
  const _SessionsPage({required this.onNewSession});

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (_, provider, child) {
        final sessions = provider.sessions;

        if (sessions.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text('暂无会话',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('点击右下角 + 创建新会话',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadSessions(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            itemBuilder: (_, i) {
              final session = sessions[i];
              return UnifiedSessionCard(
                session: session,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          SessionDetailScreen(session: session),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
