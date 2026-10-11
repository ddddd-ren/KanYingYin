/// 媒体库作品的本地用户状态，媒体成员标识用于分组变化后的关联。
class MediaLibraryUserState {
  const MediaLibraryUserState({
    this.favorite = false,
    this.watchLater = false,
    this.collections = const <String>[],
    this.mediaIds = const <String>[],
    this.updatedAt,
    this.categoryOverride,
    this.genreOverride,
  });

  static const int maxCollectionLength = 32;
  static const int maxCollections = 20;

  static const MediaLibraryUserState empty = MediaLibraryUserState();

  final bool favorite;
  final bool watchLater;
  final List<String> collections;
  final List<String> mediaIds;
  final DateTime? updatedAt;
  final List<String>? categoryOverride;
  final List<String>? genreOverride;

  bool get hasClassificationOverride =>
      categoryOverride != null || genreOverride != null;

  bool get isEmpty =>
      !favorite &&
      !watchLater &&
      collections.isEmpty &&
      !hasClassificationOverride;

  MediaLibraryUserState copyWith({
    bool? favorite,
    bool? watchLater,
    Iterable<String>? collections,
    Iterable<String>? mediaIds,
    DateTime? updatedAt,
    Iterable<String>? categoryOverride,
    Iterable<String>? genreOverride,
    bool clearCategoryOverride = false,
    bool clearGenreOverride = false,
  }) {
    return MediaLibraryUserState(
      favorite: favorite ?? this.favorite,
      watchLater: watchLater ?? this.watchLater,
      collections: collections == null
          ? this.collections
          : normalizeCollections(collections),
      updatedAt: updatedAt ?? this.updatedAt,
      mediaIds: mediaIds == null
          ? this.mediaIds
          : List<String>.unmodifiable(
              mediaIds.where((id) => id.isNotEmpty).toSet()),
      categoryOverride: clearCategoryOverride
          ? null
          : categoryOverride == null
              ? this.categoryOverride
              : _readOverride(categoryOverride.toList(), categories: true),
      genreOverride: clearGenreOverride
          ? null
          : genreOverride == null
              ? this.genreOverride
              : _readOverride(genreOverride.toList()),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (favorite) 'favorite': true,
        if (watchLater) 'watchLater': true,
        if (collections.isNotEmpty) 'collections': collections,
        if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
        if (categoryOverride != null)
          'categoryOverride': _readOverride(categoryOverride, categories: true),
        if (genreOverride != null) 'genreOverride': _readOverride(genreOverride),
        if (updatedAt != null)
          'updatedAtMillis': updatedAt!.millisecondsSinceEpoch,
      };

  factory MediaLibraryUserState.fromJson(Map<Object?, Object?> json) {
    final rawCollections = json['collections'];
    final collections = rawCollections is Iterable
        ? normalizeCollections(rawCollections.map<Object?>((value) => value))
        : const <String>[];
    final updatedAtMillis = _asInt(json['updatedAtMillis']);
    return MediaLibraryUserState(
      favorite: json['favorite'] == true,
      watchLater: json['watchLater'] == true,
      collections: collections,
      mediaIds: json['mediaIds'] is List
          ? List<String>.unmodifiable((json['mediaIds'] as List)
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet())
          : const <String>[],
      updatedAt: updatedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updatedAtMillis, isUtc: true)
              .toLocal(),
      categoryOverride:
          _readOverride(json['categoryOverride'], categories: true),
      genreOverride: _readOverride(json['genreOverride']),
    );
  }

  static List<String>? _readOverride(Object? raw, {bool categories = false}) {
    if (raw == null) return null;
    if (raw is! List ||
        raw.length > 50 ||
        raw.any((value) =>
            value is! String || value.trim().isEmpty || value.length > 64)) {
      throw const FormatException('人工分类或题材无效');
    }
    final values = raw.cast<String>().map((value) => value.trim()).toSet();
    if (categories &&
        (values.any((value) => !const {'电影', '动漫', '电视剧'}.contains(value)) ||
            (values.contains('动漫') && values.contains('电视剧')))) {
      throw const FormatException('人工分类无效，动漫与电视剧不能同时选择');
    }
    return List<String>.unmodifiable(values);
  }

  static List<String>? mergeClassificationOverride(
      List<String>? existing, List<String>? incoming) {
    if (existing == null) return incoming;
    if (incoming == null) return existing;
    final existingValues = existing.toSet();
    final incomingValues = incoming.toSet();
    if (existingValues.length != incomingValues.length ||
        !existingValues.containsAll(incomingValues)) {
      throw const MediaLibraryClassificationConflict();
    }
    return existing;
  }

  static List<String> normalizeCollections(Iterable<Object?> values) {
    final result = <String>[];
    final identities = <String>{};
    for (final value in values) {
      final collection = value?.toString().trim() ?? '';
      if (collection.isEmpty || collection.length > maxCollectionLength) {
        continue;
      }
      if (!identities.add(collection.toLowerCase())) continue;
      result.add(collection);
      if (result.length == maxCollections) break;
    }
    return List<String>.unmodifiable(result);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

final class MediaLibraryClassificationConflict implements Exception {
  const MediaLibraryClassificationConflict();

  @override
  String toString() => '人工分类或题材存在冲突，请先恢复自动或统一选择后重试';
}
