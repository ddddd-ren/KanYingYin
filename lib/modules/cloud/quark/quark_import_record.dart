enum QuarkImportStatus { pending, succeeded, failed, timedOut, cancelled }

class QuarkImportRecord {
  const QuarkImportRecord({
    required this.sourceId,
    required this.shareId,
    required this.sharedFileId,
    required this.targetDirectoryId,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.taskId,
  });

  final String sourceId;
  final String shareId;
  final String sharedFileId;
  final String targetDirectoryId;
  final String displayName;
  final QuarkImportStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? taskId;

  String get idempotencyKey =>
      '$sourceId|$shareId|$sharedFileId|$targetDirectoryId';

  bool get blocksDuplicate =>
      status == QuarkImportStatus.pending ||
      status == QuarkImportStatus.succeeded;

  QuarkImportRecord copyWith({
    QuarkImportStatus? status,
    DateTime? updatedAt,
    String? taskId,
  }) =>
      QuarkImportRecord(
        sourceId: sourceId,
        shareId: shareId,
        sharedFileId: sharedFileId,
        targetDirectoryId: targetDirectoryId,
        displayName: displayName,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        taskId: taskId ?? this.taskId,
      );

  factory QuarkImportRecord.fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) throw const FormatException();
      return value;
    }

    final status = QuarkImportStatus.values.firstWhere(
      (value) => value.name == json['status'],
      orElse: () => throw const FormatException(),
    );
    final createdAt = DateTime.tryParse(requiredString('createdAt'));
    final updatedAt = DateTime.tryParse(requiredString('updatedAt'));
    if (createdAt == null || updatedAt == null) throw const FormatException();
    return QuarkImportRecord(
      sourceId: requiredString('sourceId'),
      shareId: requiredString('shareId'),
      sharedFileId: requiredString('sharedFileId'),
      targetDirectoryId: requiredString('targetDirectoryId'),
      displayName: requiredString('displayName'),
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      taskId: json['taskId'] is String ? json['taskId'] as String : null,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'sourceId': sourceId,
        'shareId': shareId,
        'sharedFileId': sharedFileId,
        'targetDirectoryId': targetDirectoryId,
        'displayName': displayName,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'taskId': taskId,
      };
}
