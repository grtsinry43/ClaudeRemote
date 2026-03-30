class Approval {
  final String id;
  final String sessionId;
  final String toolName;
  final Map<String, dynamic> toolInput;
  final String description;
  final String kind; // 'tool_approval' or 'ask_user'
  final String status;
  final DateTime createdAt;

  Approval({
    required this.id,
    required this.sessionId,
    required this.toolName,
    required this.toolInput,
    required this.description,
    required this.kind,
    required this.status,
    required this.createdAt,
  });

  factory Approval.fromJson(Map<String, dynamic> json) {
    return Approval(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      toolName: json['toolName'] as String,
      toolInput: Map<String, dynamic>.from(json['toolInput'] as Map),
      description: json['description'] as String,
      kind: json['kind'] as String? ?? 'tool_approval',
      status: json['status'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  bool get isToolApproval => kind == 'tool_approval';
  bool get isAskUser => kind == 'ask_user';

  /// For AskUserQuestion: parsed questions list
  List<AskQuestion> get questions {
    final raw = toolInput['questions'];
    if (raw is! List) return [];
    return raw
        .map((q) => AskQuestion.fromJson(q as Map<String, dynamic>))
        .toList();
  }
}

class AskQuestion {
  final String question;
  final String header;
  final List<AskOption> options;
  final bool multiSelect;

  AskQuestion({
    required this.question,
    required this.header,
    required this.options,
    required this.multiSelect,
  });

  factory AskQuestion.fromJson(Map<String, dynamic> json) {
    return AskQuestion(
      question: json['question'] as String? ?? '',
      header: json['header'] as String? ?? '',
      options: (json['options'] as List?)
              ?.map((o) => AskOption.fromJson(o as Map<String, dynamic>))
              .toList() ??
          [],
      multiSelect: json['multiSelect'] as bool? ?? false,
    );
  }
}

class AskOption {
  final String label;
  final String description;

  AskOption({required this.label, required this.description});

  factory AskOption.fromJson(Map<String, dynamic> json) {
    return AskOption(
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }
}
