import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/approval.dart';

/// Shows a tool approval request as a bottom sheet.
/// Returns true if approved, false if denied.
Future<bool?> showToolApprovalSheet(
    BuildContext context, Approval approval) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _ToolApprovalSheet(approval: approval),
  );
}

/// Shows an AskUserQuestion as a bottom sheet.
/// Returns the answers map, or null if dismissed.
Future<Map<String, String>?> showAskUserSheet(
    BuildContext context, Approval approval) {
  return showModalBottomSheet<Map<String, String>>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (_) => _AskUserSheet(approval: approval),
  );
}

// ─── Tool Approval ────────────────────────────────────────

class _ToolApprovalSheet extends StatelessWidget {
  final Approval approval;
  const _ToolApprovalSheet({required this.approval});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inputPreview = const JsonEncoder.withIndent('  ')
        .convert(approval.toolInput);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    color: Colors.orange, size: 24),
                const SizedBox(width: 10),
                Text(
                  '需要审批',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_toolIcon(approval.toolName),
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        approval.toolName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    inputPreview,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 12,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('批准'),
                  ),
                ),
              ],
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
        _ => Icons.extension,
      };
}

// ─── AskUserQuestion ──────────────────────────────────────

class _AskUserSheet extends StatefulWidget {
  final Approval approval;
  const _AskUserSheet({required this.approval});

  @override
  State<_AskUserSheet> createState() => _AskUserSheetState();
}

class _AskUserSheetState extends State<_AskUserSheet> {
  // Single select: question -> selected label (or custom text)
  final Map<String, String> _answers = {};
  // Multi select: question -> set of selected labels
  final Map<String, Set<String>> _multiSelections = {};
  // Track which questions are using "Other" custom input
  final Map<String, bool> _usingOther = {};
  final Map<String, TextEditingController> _otherControllers = {};

  @override
  void dispose() {
    for (final c in _otherControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectSingle(String questionKey, String label) {
    setState(() {
      _answers[questionKey] = label;
      _usingOther[questionKey] = false;
    });
  }

  void _toggleMulti(String questionKey, String label) {
    setState(() {
      final set = _multiSelections.putIfAbsent(questionKey, () => {});
      if (set.contains(label)) {
        set.remove(label);
      } else {
        set.add(label);
      }
      _answers[questionKey] = set.join(', ');
      _usingOther[questionKey] = false;
    });
  }

  void _selectOther(String questionKey) {
    setState(() {
      _usingOther[questionKey] = true;
      _otherControllers.putIfAbsent(
          questionKey, () => TextEditingController());
      // Clear previous selection
      _answers.remove(questionKey);
      _multiSelections.remove(questionKey);
    });
  }

  void _updateOtherText(String questionKey, String text) {
    setState(() {
      if (text.trim().isNotEmpty) {
        _answers[questionKey] = text.trim();
      } else {
        _answers.remove(questionKey);
      }
    });
  }

  bool get _allAnswered {
    final questions = widget.approval.questions;
    return questions.every((q) =>
        _answers.containsKey(q.question) &&
        _answers[q.question]!.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questions = widget.approval.questions;

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.help_outline,
                      color: theme.colorScheme.secondary, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Claude 有问题要问你',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: questions.length,
                  itemBuilder: (_, i) {
                    final q = questions[i];
                    final isMulti = q.multiSelect;
                    final selectedLabel = _answers[q.question];
                    final selectedSet =
                        _multiSelections[q.question] ?? {};
                    final isOther = _usingOther[q.question] ?? false;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              q.header,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme
                                    .colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            q.question,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (isMulti)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '可多选',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme
                                      .colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          // Options
                          ...q.options.map((opt) {
                            final selected = isMulti
                                ? selectedSet.contains(opt.label)
                                : selectedLabel == opt.label && !isOther;
                            return _OptionTile(
                              option: opt,
                              selected: selected,
                              multiSelect: isMulti,
                              onTap: () => isMulti
                                  ? _toggleMulti(q.question, opt.label)
                                  : _selectSingle(
                                      q.question, opt.label),
                            );
                          }),
                          // "Other" option
                          _OtherOptionTile(
                            selected: isOther,
                            controller: _otherControllers.putIfAbsent(
                                q.question,
                                () => TextEditingController()),
                            onTap: () => _selectOther(q.question),
                            onChanged: (text) =>
                                _updateOtherText(q.question, text),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _allAnswered
                      ? () => Navigator.pop(context, _answers)
                      : null,
                  child: const Text('提交回答'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final AskOption option;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;

  const _OptionTile({
    required this.option,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primaryContainer
                : null,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? (multiSelect
                        ? Icons.check_box
                        : Icons.radio_button_checked)
                    : (multiSelect
                        ? Icons.check_box_outline_blank
                        : Icons.radio_button_unchecked),
                size: 20,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (option.description.isNotEmpty)
                      Text(
                        option.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: selected
                              ? theme.colorScheme.onPrimaryContainer
                                  .withValues(alpha: 0.8)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherOptionTile extends StatelessWidget {
  final bool selected;
  final TextEditingController controller;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  const _OtherOptionTile({
    required this.selected,
    required this.controller,
    required this.onTap,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primaryContainer : null,
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: selected
                    ? TextField(
                        controller: controller,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: '输入你的回答...',
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: onChanged,
                      )
                    : Text(
                        '其他（自定义回答）',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
