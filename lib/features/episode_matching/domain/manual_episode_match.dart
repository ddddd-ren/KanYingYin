enum ManualEpisodeAssignmentMode { mapped, keepOriginal, restoreAutomatic }

final class ManualEpisodeMatchItem {
  const ManualEpisodeMatchItem({
    required this.resourceId,
    required this.originalName,
    this.parentName,
    this.existingSeasonNumber,
    this.existingEpisodeNumber,
    this.automaticSeasonNumber,
    this.automaticEpisodeNumber,
    this.manualOverride = false,
  });

  final String resourceId;
  final String originalName;
  final String? parentName;
  final int? existingSeasonNumber;
  final int? existingEpisodeNumber;
  final int? automaticSeasonNumber;
  final int? automaticEpisodeNumber;
  final bool manualOverride;
}

final class ManualEpisodeAssignment {
  const ManualEpisodeAssignment._({
    required this.resourceId,
    required this.mode,
    this.seasonNumber,
    this.episodeNumber,
  });

  factory ManualEpisodeAssignment.mapped({
    required String resourceId,
    required int seasonNumber,
    required int episodeNumber,
  }) {
    return ManualEpisodeAssignment._(
      resourceId: resourceId,
      mode: ManualEpisodeAssignmentMode.mapped,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    );
  }

  factory ManualEpisodeAssignment.keepOriginal(String resourceId) {
    return ManualEpisodeAssignment._(
      resourceId: resourceId,
      mode: ManualEpisodeAssignmentMode.keepOriginal,
    );
  }

  factory ManualEpisodeAssignment.restoreAutomatic(String resourceId) {
    return ManualEpisodeAssignment._(
      resourceId: resourceId,
      mode: ManualEpisodeAssignmentMode.restoreAutomatic,
    );
  }

  final String resourceId;
  final ManualEpisodeAssignmentMode mode;
  final int? seasonNumber;
  final int? episodeNumber;
}

List<String> validateManualEpisodeAssignments({
  required List<ManualEpisodeMatchItem> items,
  required List<ManualEpisodeAssignment> assignments,
  required int selectedSeasonNumber,
  required Set<int> validEpisodeNumbers,
}) {
  final errors = <String>[];
  final itemIds = <String>{};
  for (final item in items) {
    if (!itemIds.add(item.resourceId)) {
      errors.add('资源标识必须唯一：${item.resourceId}');
    }
  }

  final assignmentIds = <String>{};
  for (final assignment in assignments) {
    final resourceId = assignment.resourceId;
    if (!itemIds.contains(resourceId)) {
      errors.add('匹配结果包含未知资源：$resourceId');
    }
    if (!assignmentIds.add(resourceId)) {
      errors.add('同一资源只能提交一个操作：$resourceId');
    }
    if (assignment.mode != ManualEpisodeAssignmentMode.mapped) continue;

    final seasonNumber = assignment.seasonNumber;
    final episodeNumber = assignment.episodeNumber;
    if (seasonNumber != selectedSeasonNumber) {
      errors.add('$resourceId 的季度不是当前选择的第 $selectedSeasonNumber 季');
    }
    if (episodeNumber == null ||
        episodeNumber <= 0 ||
        !validEpisodeNumbers.contains(episodeNumber)) {
      errors.add('$resourceId 选择了不存在的第 ${episodeNumber ?? 0} 集');
    }
  }
  return List<String>.unmodifiable(errors);
}
