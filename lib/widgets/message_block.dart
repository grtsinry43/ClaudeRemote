import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Parsed representation of a single content block from a session message.
///
/// Raw JSONL format from Agent SDK getSessionMessages():
///   { type: "user"|"assistant", message: { role, content } }
///
/// content can be:
///   - String  (user plain text)
///   - A list of content blocks:
///       { type: "text", text: "..." }
///       { type: "tool_use", name: "...", id: "...", input: {...} }
///       { type: "tool_result", tool_use_id: "...", content: ... }
///       { type: "thinking", thinking: "..." }
class ParsedBlock {
  final String blockType; // text, tool_use, tool_result, thinking, user_text
  final String role;      // user, assistant
  final String text;
  final String? toolName;
  final Map<String, dynamic>? toolInput;

  ParsedBlock({
    required this.blockType,
    required this.role,
    required this.text,
    this.toolName,
    this.toolInput,
  });

  bool get isUserText => role == 'user' && blockType == 'user_text';
  bool get isAssistantText => role == 'assistant' && blockType == 'text';
  bool get isToolUse => blockType == 'tool_use';
  bool get isToolResult => blockType == 'tool_result';
  bool get isThinking => blockType == 'thinking';

  bool get isVisible {
    if (isThinking && text.isEmpty) return false;
    if (text.isEmpty && toolName == null) return false;
    return true;
  }
}

/// Parse a raw SessionMessage into displayable blocks.
List<ParsedBlock> parseMessage(Map<String, dynamic> raw) {
  final type = raw['type'] as String? ?? '';
  final message = raw['message'];
  if (message is! Map) return [];

  final content = message['content'];

  if (content is String) {
    if (content.isEmpty) return [];
    return [
      ParsedBlock(blockType: 'user_text', role: type, text: content),
    ];
  }

  if (content is! List) return [];

  final blocks = <ParsedBlock>[];
  for (final block in content) {
    if (block is! Map) continue;
    final bt = block['type'] as String? ?? '';

    switch (bt) {
      case 'text':
        final text = block['text'] as String? ?? '';
        if (text.isNotEmpty) {
          blocks.add(ParsedBlock(blockType: 'text', role: type, text: text));
        }
      case 'tool_use':
        final name = block['name'] as String? ?? 'unknown';
        final input = block['input'] is Map
            ? Map<String, dynamic>.from(block['input'] as Map)
            : <String, dynamic>{};
        blocks.add(ParsedBlock(
          blockType: 'tool_use',
          role: type,
          text: _toolInputSummary(name, input),
          toolName: name,
          toolInput: input,
        ));
      case 'tool_result':
        final resultContent = block['content'];
        String text;
        if (resultContent is String) {
          text = resultContent;
        } else if (resultContent is List && resultContent.isNotEmpty) {
          text = resultContent
              .where((b) => b is Map && b['type'] == 'text')
              .map((b) => (b as Map)['text'] as String? ?? '')
              .join('\n');
        } else {
          text = '';
        }
        if (text.isNotEmpty) {
          blocks.add(ParsedBlock(
            blockType: 'tool_result',
            role: type,
            text: text.length > 500 ? '${text.substring(0, 500)}...' : text,
          ));
        }
      case 'thinking':
        final thinking = block['thinking'] as String? ?? '';
        if (thinking.isNotEmpty) {
          blocks.add(
              ParsedBlock(blockType: 'thinking', role: type, text: thinking));
        }
    }
  }
  return blocks;
}

String _toolInputSummary(String name, Map<String, dynamic> input) {
  return switch (name) {
    'Read' => input['file_path'] as String? ?? '',
    'Edit' || 'Write' => input['file_path'] as String? ?? '',
    'Bash' => () {
        final cmd = input['command'] as String? ?? '';
        return cmd.length > 120 ? '${cmd.substring(0, 120)}...' : cmd;
      }(),
    'Glob' => input['pattern'] as String? ?? '',
    'Grep' => 'pattern: ${input['pattern'] ?? ''}',
    'Agent' => input['description'] as String? ?? '',
    'TaskCreate' || 'TaskUpdate' =>
      input['subject'] as String? ?? json.encode(input),
    _ => () {
        final s = json.encode(input);
        return s.length > 120 ? '${s.substring(0, 120)}...' : s;
      }(),
  };
}

// ─── Widgets ──────────────────────────────────────────────

class MessageBlockWidget extends StatelessWidget {
  final ParsedBlock block;
  const MessageBlockWidget({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    if (block.isUserText) return _UserText(block: block);
    if (block.isAssistantText) return _AssistantText(block: block);
    if (block.isToolUse) return _ToolUseRow(block: block);
    if (block.isToolResult) return _ToolResultRow(block: block);
    if (block.isThinking) return _ThinkingRow(block: block);
    return const SizedBox.shrink();
  }
}

// ─── User text ────────────────────────────────────────────

class _UserText extends StatelessWidget {
  final ParsedBlock block;
  const _UserText({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'You',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            block.text,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Divider(height: 20),
        ],
      ),
    );
  }
}

// ─── Assistant text (Markdown) ────────────────────────────

class _AssistantText extends StatelessWidget {
  final ParsedBlock block;
  const _AssistantText({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined,
                  size: 16, color: theme.colorScheme.secondary),
              const SizedBox(width: 6),
              Text(
                'Claude',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          MarkdownBody(
            data: block.text,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium,
              code: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              codeblockPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tool use ─────────────────────────────────────────────

class _ToolUseRow extends StatelessWidget {
  final ParsedBlock block;
  const _ToolUseRow({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.primaryContainer,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            Icon(_toolIcon(block.toolName ?? ''),
                size: 15, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              block.toolName ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                block.text,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _toolIcon(String name) => switch (name) {
        'Bash' => Icons.terminal,
        'Edit' || 'Write' => Icons.edit_document,
        'Read' => Icons.description,
        'Glob' || 'Grep' => Icons.search,
        'Agent' => Icons.smart_toy,
        'WebFetch' || 'WebSearch' => Icons.language,
        'TaskCreate' || 'TaskUpdate' || 'TaskGet' || 'TaskList' =>
          Icons.checklist,
        'ToolSearch' => Icons.build_circle,
        _ => Icons.extension,
      };
}

// ─── Tool result (collapsible) ────────────────────────────

class _ToolResultRow extends StatefulWidget {
  final ParsedBlock block;
  const _ToolResultRow({required this.block});

  @override
  State<_ToolResultRow> createState() => _ToolResultRowState();
}

class _ToolResultRowState extends State<_ToolResultRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = widget.block.text.length > 100
        ? '${widget.block.text.substring(0, 100)}...'
        : widget.block.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.output,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('输出',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _expanded ? widget.block.text : preview,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Thinking (collapsible) ───────────────────────────────

class _ThinkingRow extends StatefulWidget {
  final ParsedBlock block;
  const _ThinkingRow({required this.block});

  @override
  State<_ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<_ThinkingRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology,
                      size: 14, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 6),
                  Text('思考过程',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.tertiary,
                      )),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 6),
                SelectableText(
                  widget.block.text,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
