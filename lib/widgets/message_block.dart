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
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            block.text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
              height: 1.5,
            ),
          ),
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
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: MarkdownBody(
        data: block.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          code: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          codeblockPadding: const EdgeInsets.all(12),
        ),
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
    final onSurface = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '${block.toolName}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
          TextSpan(
            text: '  ${block.text}',
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: onSurface.withValues(alpha: 0.45),
            ),
          ),
        ]),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
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
    final onSurface = theme.colorScheme.onSurface;
    final preview = widget.block.text.length > 80
        ? '${widget.block.text.substring(0, 80)}...'
        : widget.block.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _expanded ? '- output' : '+ output',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: SelectableText(
                  widget.block.text,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: onSurface.withValues(alpha: 0.5),
                    height: 1.4,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  preview,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: onSurface.withValues(alpha: 0.35),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
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
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _expanded ? '- thinking' : '+ thinking',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
                color: onSurface.withValues(alpha: 0.35),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: SelectableText(
                  widget.block.text,
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withValues(alpha: 0.45),
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
