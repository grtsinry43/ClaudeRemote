class Session {
  final String sessionId;
  final String summary;
  final int lastModified;
  final String? customTitle;
  final String? firstPrompt;
  final String? gitBranch;
  final String? cwd;
  final int? createdAt;
  final bool isActive;

  Session({
    required this.sessionId,
    required this.summary,
    required this.lastModified,
    this.customTitle,
    this.firstPrompt,
    this.gitBranch,
    this.cwd,
    this.createdAt,
    this.isActive = false,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      sessionId: json['sessionId'] as String,
      summary: (json['summary'] as String?) ?? '',
      lastModified: (json['lastModified'] as num?)?.toInt() ?? 0,
      customTitle: json['customTitle'] as String?,
      firstPrompt: json['firstPrompt'] as String?,
      gitBranch: json['gitBranch'] as String?,
      cwd: json['cwd'] as String?,
      createdAt: (json['createdAt'] as num?)?.toInt(),
      isActive: json['isActive'] as bool? ?? false,
    );
  }

  String get displayName =>
      customTitle ?? (summary.isNotEmpty ? summary : sessionId.substring(0, 8));

  DateTime get lastModifiedAt =>
      DateTime.fromMillisecondsSinceEpoch(lastModified);
}
