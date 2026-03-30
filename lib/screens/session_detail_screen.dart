import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/session.dart';
import '../models/approval.dart';
import '../providers/session_provider.dart';
import '../widgets/message_block.dart';
import '../widgets/approval_sheet.dart';

class SessionDetailScreen extends StatefulWidget {
  final Session session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  List<ParsedBlock> _blocks = [];
  bool _loading = true;
  bool _sending = false;
  bool _followMode = true;

  StreamSubscription<String>? _messageSub;
  StreamSubscription<Approval>? _approvalSub;
  StreamSubscription<Map<String, dynamic>>? _errorSub;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMessages();

    final provider = context.read<SessionProvider>();

    // Subscribe to real-time message updates for this session
    _messageSub = provider.messageUpdates
        .where((id) => id == widget.session.sessionId)
        .listen((_) => _loadMessages());

    // Subscribe to approval requests for this session
    _approvalSub = provider.approvalRequests
        .where((a) => a.sessionId == widget.session.sessionId)
        .listen(_handleApproval);

    // Subscribe to errors for this session
    _errorSub = provider.errors
        .where((e) =>
            e['sessionId'] == widget.session.sessionId ||
            e['sessionId'] == 'pending')
        .listen((e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e['error']}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    });
  }

  Future<void> _handleApproval(Approval approval) async {
    if (!mounted) return;
    final provider = context.read<SessionProvider>();

    if (approval.isAskUser) {
      final answers = await showAskUserSheet(context, approval);
      if (answers != null) {
        provider.respondToApproval(approval.id, true, answers: answers);
      } else {
        provider.respondToApproval(approval.id, false);
      }
    } else {
      final allowed = await showToolApprovalSheet(context, approval);
      provider.respondToApproval(approval.id, allowed ?? false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // Consider "at bottom" if within 50px of the end
    final atBottom = pos.pixels >= pos.maxScrollExtent - 50;
    if (_followMode != atBottom) {
      setState(() => _followMode = atBottom);
    }
  }

  void _scrollToBottom() {
    if (!_followMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadMessages() async {
    try {
      final provider = context.read<SessionProvider>();
      final rawMsgs = await provider.loadMessages(widget.session.sessionId);
      if (!mounted) return;

      final blocks = <ParsedBlock>[];
      for (final raw in rawMsgs) {
        blocks.addAll(parseMessage(raw).where((b) => b.isVisible));
      }

      setState(() {
        _blocks = blocks;
        _loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _jumpToBottom() {
    setState(() => _followMode = true);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    _inputController.clear();

    // Immediately show user message in the list
    setState(() {
      _sending = true;
      _followMode = true;
      _blocks.add(ParsedBlock(
        blockType: 'user_text',
        role: 'user',
        text: text,
      ));
    });
    _scrollToBottom();

    final provider = context.read<SessionProvider>();
    await provider.sendMessage(
      text,
      sessionId: widget.session.sessionId,
    );

    if (mounted) {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.session.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.session.cwd != null)
              Text(
                widget.session.cwd!,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          Consumer<SessionProvider>(
            builder: (_, provider, child) {
              final current = provider.sessions.where(
                (s) => s.sessionId == widget.session.sessionId,
              );
              final isActive = current.isNotEmpty && current.first.isActive;
              if (!isActive) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.stop_circle_outlined),
                tooltip: '停止',
                onPressed: () =>
                    provider.stopSession(widget.session.sessionId),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      Consumer<SessionProvider>(
                        builder: (_, provider, child) {
                          final streamText = provider.getStreamingText(
                              widget.session.sessionId);
                          final hasStream = streamText.isNotEmpty;
                          final totalItems =
                              _blocks.length + (hasStream ? 1 : 0);

                          if (totalItems == 0) {
                            return Center(
                              child: Text(
                                '暂无消息',
                                style: TextStyle(
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            );
                          }

                          // Auto-scroll when streaming and in follow mode
                          if (hasStream) _scrollToBottom();

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(
                                16, 8, 16, 80),
                            itemCount: totalItems,
                            itemBuilder: (_, i) {
                              if (i < _blocks.length) {
                                return MessageBlockWidget(
                                    block: _blocks[i]);
                              }

                              // Live streaming text
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 14,
                                          height: 14,
                                          child:
                                              CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme
                                                .colorScheme.secondary,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Claude 正在回复...',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: theme
                                                .colorScheme.secondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    SelectableText(
                                      streamText,
                                      style: TextStyle(
                                        color: theme
                                            .colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),

                      // "Jump to bottom" FAB — only visible when not following
                      if (!_followMode)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: FloatingActionButton.small(
                            onPressed: _jumpToBottom,
                            child: const Icon(Icons.keyboard_arrow_down),
                          ),
                        ),
                    ],
                  ),
          ),

          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(
                        hintText: '继续对话...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _approvalSub?.cancel();
    _errorSub?.cancel();
    _inputController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }
}
