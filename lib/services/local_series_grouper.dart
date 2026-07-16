import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:path/path.dart' as p;

class LocalSeriesGrouper {
  const LocalSeriesGrouper();

  List<LocalVideoGroup> group(Iterable<LocalFileItem> items) {
    final buckets = <_SeriesBucket>[];
    for (final item in items.where((item) => item.isVideo)) {
      var descriptor = _SeriesDescriptor.fromItem(item);
      descriptor = _reuseKnownBase(buckets, descriptor);
      final bucket = _findBucket(buckets, descriptor);
      if (bucket == null) {
        buckets.add(_SeriesBucket(descriptor)..items.add(item));
      } else {
        bucket.items.add(item);
        bucket.merge(descriptor);
      }
    }

    return buckets.map((bucket) {
      final episodes = bucket.items;
      final sorted = List<LocalFileItem>.of(episodes)..sort(_compareEpisodes);
      return LocalVideoGroup(
        episodes: sorted,
        titleOverride: bucket.displayTitle,
        searchTitleOverride: bucket.baseTitle,
      );
    }).toList(growable: false);
  }

  _SeriesDescriptor _reuseKnownBase(
    List<_SeriesBucket> buckets,
    _SeriesDescriptor descriptor,
  ) {
    if (descriptor.hasTitleOverride) return descriptor;
    for (final bucket in buckets) {
      final known = bucket.descriptor;
      if (known.hasTitleOverride) continue;
      if (known.key == descriptor.key ||
          _isRelatedTitle(known.key, descriptor.key) ||
          _isRelatedTitle(descriptor.key, known.key)) {
        if (known.baseTitle.length <= descriptor.baseTitle.length) {
          return descriptor.withBase(known);
        }
      }
    }
    return descriptor;
  }

  _SeriesBucket? _findBucket(
    List<_SeriesBucket> buckets,
    _SeriesDescriptor descriptor,
  ) {
    for (final bucket in buckets) {
      if (_sameCollection(bucket.descriptor, descriptor)) {
        return bucket;
      }
    }
    return null;
  }

  bool _sameCollection(_SeriesDescriptor left, _SeriesDescriptor right) {
    if (left.collectionKey != right.collectionKey) return false;
    if (left.directoryKey == right.directoryKey) return true;
    if (left.key == right.key) return true;
    if (_isVariantKey(left.key, right.key)) return true;
    return _isVariantKey(right.key, left.key);
  }

  bool _isVariantKey(String base, String variant) {
    if (!_hasEnoughBaseLength(base) || !variant.startsWith(base)) return false;
    final suffix = variant.substring(base.length);
    if (suffix.isEmpty || suffix.length > 24) return false;
    if (RegExp(r'^\d+$').hasMatch(suffix)) return true;
    if (RegExp(r'^(i|ii|iii|iv|v|vi|vii|viii|ix|x)+$').hasMatch(suffix)) {
      return true;
    }
    const knownSuffixes = {
      '恋',
      '续',
      '新',
      '完结篇',
      '剧场版',
      '映画',
      'movie',
      'themovie',
      'ova',
      'oad',
      'sp',
      'special',
      'lite',
      '番外篇',
      '特别篇',
      '总集篇',
      '外传',
    };
    return knownSuffixes.contains(suffix);
  }

  bool _isRelatedTitle(String base, String variant) {
    if (_isVariantKey(base, variant)) return true;
    if (!_hasEnoughBaseLength(base) || !variant.startsWith(base)) return false;
    final suffix = variant.substring(base.length);
    if (suffix.isEmpty || suffix.length > 24) return false;
    return base.length >= 6 ||
        (base.length >= 4 && RegExp(r'[\u4e00-\u9fff]').hasMatch(base));
  }

  bool _hasEnoughBaseLength(String value) {
    if (value.length >= 4) return true;
    return value.length >= 2 && RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
  }

  int _compareEpisodes(LocalFileItem a, LocalFileItem b) {
    final season = _seasonSortKey(a).compareTo(_seasonSortKey(b));
    if (season != 0) return season;
    final episode = (a.episodeInfo?.episodeNumber ?? 0)
        .compareTo(b.episodeInfo?.episodeNumber ?? 0);
    if (episode != 0) return episode;
    return _compareNaturalName(a.name, b.name);
  }

  int _seasonSortKey(LocalFileItem item) {
    if (item.episodeInfo == null) return 0;
    final season = item.episodeInfo?.seasonNumber;
    return season == null || season <= 0 ? 999 : season;
  }

  int _compareNaturalName(String left, String right) {
    final leftParts = _splitNaturalParts(left);
    final rightParts = _splitNaturalParts(right);
    final length = leftParts.length < rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < length; i++) {
      final cmp = leftParts[i].compareTo(rightParts[i]);
      if (cmp != 0) return cmp;
    }
    return leftParts.length.compareTo(rightParts.length);
  }

  List<_NaturalNamePart> _splitNaturalParts(String value) {
    final matches = RegExp(r'\d+|\D+').allMatches(value);
    return [
      for (final match in matches) _NaturalNamePart.from(match.group(0) ?? ''),
    ];
  }
}

class LocalVideoGroup {
  final List<LocalFileItem> episodes;
  final String? titleOverride;
  final String? searchTitleOverride;

  const LocalVideoGroup({
    required this.episodes,
    this.titleOverride,
    this.searchTitleOverride,
  });

  LocalFileItem get firstEpisode => episodes.first;

  int get episodeCount => episodes.length;

  bool get hasMultipleEpisodes => episodeCount > 1;

  String get title {
    final override = titleOverride?.trim();
    if (override != null && override.isNotEmpty) return override;

    final first = firstEpisode;
    final info = first.episodeInfo;
    final seriesName = info?.seriesName.trim();
    if (seriesName != null && seriesName.isNotEmpty) {
      final season = info?.seasonNumber;
      if (season != null && season > 0) {
        return '$seriesName S${season.toString().padLeft(2, '0')}';
      }
      return seriesName;
    }
    final parentName = p.basename(p.dirname(first.path)).trim();
    return parentName.isEmpty
        ? p.basenameWithoutExtension(first.name)
        : parentName;
  }

  String get searchTitle {
    final override = searchTitleOverride?.trim();
    return override == null || override.isEmpty ? title : override;
  }

  String get subtitle {
    if (episodes.length == 1) {
      return firstEpisode.formattedSize;
    }
    final firstNumber = firstEpisode.episodeInfo?.episodeNumber;
    final lastNumber = episodes.last.episodeInfo?.episodeNumber;
    if (firstNumber != null && lastNumber != null) {
      return '$episodeCount 集 · 第 $firstNumber-$lastNumber 集';
    }
    return '$episodeCount 集';
  }

  String? get cover {
    String? thumbnailCover;
    for (final episode in episodes) {
      final value = episode.cover;
      if (value == null || value.isEmpty) continue;
      if (!_isGeneratedThumbnail(value)) {
        return value;
      }
      thumbnailCover ??= value;
    }
    return thumbnailCover;
  }

  bool get needsOnlinePoster {
    final currentCover = cover;
    if (currentCover == null || currentCover.isEmpty) return true;
    return _isGeneratedThumbnail(currentCover);
  }

  bool matches(String keyword) {
    final normalized = keyword.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if (title.toLowerCase().contains(normalized)) return true;
    return episodes
        .any((episode) => episode.name.toLowerCase().contains(normalized));
  }

  List<Map<String, String>> get playlistFiles {
    return episodes
        .map((episode) => {'path': episode.path, 'name': episode.name})
        .toList(growable: false);
  }

  List<Map<String, String>> get playlistFilesForPlayback {
    return episodes
        .map((episode) => {
              'path': episode.path,
              'name': episode.name,
              'title': _playbackTitle(episode),
            })
        .toList(growable: false);
  }

  String _playbackTitle(LocalFileItem episode) {
    return p.basenameWithoutExtension(episode.name);
  }

  static bool _isGeneratedThumbnail(String path) {
    return path
        .split(RegExp(r'[\\/]'))
        .any((segment) => segment == '.kanyingyin_thumbs');
  }
}

class _SeriesBucket {
  _SeriesBucket(this.descriptor);

  _SeriesDescriptor descriptor;
  final List<LocalFileItem> items = [];

  String get displayTitle => descriptor.displayTitle;

  String get baseTitle => descriptor.baseTitle;

  void merge(_SeriesDescriptor next) {
    if (descriptor.hasTitleOverride) return;
    if (next.hasTitleOverride ||
        next.baseTitle.length < descriptor.baseTitle.length) {
      descriptor = next;
    }
  }
}

class _SeriesDescriptor {
  const _SeriesDescriptor({
    required this.baseTitle,
    required this.key,
    required this.directoryKey,
    required this.collectionKey,
    required this.collectionLabel,
    required this.hasTitleOverride,
  });

  final String baseTitle;
  final String key;
  final String directoryKey;
  final String collectionKey;
  final String collectionLabel;
  final bool hasTitleOverride;

  String get displayTitle => hasTitleOverride || collectionLabel.isEmpty
      ? baseTitle
      : '$baseTitle $collectionLabel'.trim();

  factory _SeriesDescriptor.fromItem(LocalFileItem item) {
    final rawTitle = _sourceTitle(item);
    final override = item.seriesTitleOverride?.trim();
    final hasTitleOverride = override != null && override.isNotEmpty;
    final baseTitle = !hasTitleOverride ? _displayTitle(rawTitle) : override;
    final collection = _CollectionDescriptor.fromItem(item, rawTitle);
    return _SeriesDescriptor(
      baseTitle: baseTitle,
      key: _keyTitle(rawTitle),
      directoryKey: p.normalize(p.dirname(item.path)).toLowerCase(),
      collectionKey: collection.key,
      collectionLabel: collection.label,
      hasTitleOverride: hasTitleOverride,
    );
  }

  _SeriesDescriptor withBase(_SeriesDescriptor other) {
    return _SeriesDescriptor(
      baseTitle: other.baseTitle,
      key: key,
      directoryKey: directoryKey,
      collectionKey: collectionKey,
      collectionLabel: collectionLabel,
      hasTitleOverride: other.hasTitleOverride,
    );
  }

  static String _sourceTitle(LocalFileItem item) {
    final seriesName = item.episodeInfo?.seriesName.trim();
    if (seriesName != null && seriesName.isNotEmpty) {
      return seriesName;
    }
    final parentName = _seriesTitleFromDirectory(item.path);
    if (parentName.isNotEmpty) return parentName;
    return p.basenameWithoutExtension(item.name);
  }

  static String _seriesTitleFromDirectory(String filePath) {
    final parent = p.dirname(filePath);
    final parentName = p.basename(parent).trim();
    if (parentName.isEmpty) return parentName;

    if (_isCollectionDirectory(parentName)) {
      final grandParentName = p.basename(p.dirname(parent)).trim();
      if (grandParentName.isNotEmpty) return grandParentName;
    }
    return parentName;
  }

  static bool _isCollectionDirectory(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (RegExp(r'^(?:s|season)\s*\d{1,2}$', caseSensitive: false)
        .hasMatch(normalized)) {
      return true;
    }
    if (RegExp(r'^第[一二三四五六七八九十百\d]+[季期部篇章]$', unicode: true)
        .hasMatch(normalized)) {
      return true;
    }
    const markerNames = {
      '剧场版',
      '映画',
      '电影版',
      'movie',
      'the movie',
      'ova',
      'oad',
      'sp',
      'special',
      'lite',
      '番外篇',
      '特别篇',
      '总集篇',
      '外传',
      '完结篇',
      '续篇',
    };
    return markerNames.contains(normalized);
  }

  static String _displayTitle(String value) {
    final stripped = _stripCollectionMarkers(
      value,
      stripYear: true,
      stripSequelNumber: true,
    );
    return stripped.isEmpty ? value.trim() : stripped;
  }

  static String _keyTitle(String value) {
    final stripped = _stripCollectionMarkers(
      value,
      stripYear: true,
      stripSequelNumber: true,
    );
    final normalized = stripped
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s._\-:：·!！?？,，、~～]+'), '');
    return normalized.isEmpty ? value.trim().toLowerCase() : normalized;
  }

  static String _stripCollectionMarkers(
    String value, {
    required bool stripYear,
    required bool stripSequelNumber,
  }) {
    var result = value
        .replaceAll(RegExp(r'[\[\]【】「」『』（）()]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (result.isEmpty) return result;

    result = _stripReleasePrefix(result);

    result = result.replaceAll(
      RegExp(r'^(剧场版|映画|电影版|the\s+movie|movie)\s*[:：\-]?\s*',
          caseSensitive: false, unicode: true),
      '',
    );
    result = result.replaceAll(
      RegExp(r'\bweb\s*[- ]?dl\b', caseSensitive: false, unicode: true),
      ' ',
    );

    final markerPatterns = [
      RegExp(r'\s*第[一二三四五六七八九十百\d]+[季期部篇章]', unicode: true),
      RegExp(r'\s*(?:season|series)\s*\d{1,2}', caseSensitive: false),
      RegExp(r'\s*\d{1,2}(?:st|nd|rd|th)\s+season', caseSensitive: false),
      RegExp(r'[\s._\-]*s\d{1,2}\b', caseSensitive: false),
      RegExp(r'\s*(?:part|vol\.?|volume)\s*\d{1,2}', caseSensitive: false),
      RegExp(
          r'\s*(?:hq|dt|uhd|hdr|hdrip|webrip|bdrip|bluray|hdtv|tvrip|x264|x265|hevc|avc|av1|aac|flac)\b',
          caseSensitive: false),
      RegExp(r'\s*(?:ova|oad|sp|special|lite)\b', caseSensitive: false),
      RegExp(r'\s*(?:the\s+movie|movie)\b', caseSensitive: false),
      RegExp(r'\s*(剧场版|映画|电影版|番外篇|特别篇|总集篇|外传|完结篇|续篇)', unicode: true),
    ];
    for (final pattern in markerPatterns) {
      result = result.replaceAll(pattern, ' ');
    }

    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    final dashIndex = result.indexOf(RegExp(r'\s[-–—]\s'));
    if (dashIndex > 0) {
      result = result.substring(0, dashIndex).trim();
    }

    if (stripYear) {
      result = result.replaceFirst(RegExp(r'\s+(19|20)\d{2}$'), '').trim();
    }
    if (stripSequelNumber && result.length > 1) {
      result = _stripTrailingSequelNumber(result)
          .replaceFirst(
            RegExp(r'\s+(i|ii|iii|iv|v|vi|vii|viii|ix|x)$',
                caseSensitive: false),
            '',
          )
          .trim();
    }
    return result;
  }

  static String _stripReleasePrefix(String value) {
    final match = RegExp(
      r'^(?<prefix>[A-Za-z][A-Za-z0-9_-]{1,15})\s+(?<title>.+)$',
    ).firstMatch(value);
    if (match == null) return value;

    final prefix = match.namedGroup('prefix') ?? '';
    final title = match.namedGroup('title')?.trim() ?? '';
    if (title.isEmpty || !_looksLikeReleasePrefix(prefix, title)) {
      return value;
    }
    return title;
  }

  static bool _looksLikeReleasePrefix(String prefix, String title) {
    if (prefix.length < 2 || prefix.length > 16) return false;
    if (!RegExp(r'[\u4e00-\u9fff]').hasMatch(title)) return false;
    final lower = prefix.toLowerCase();
    const commonPrefixes = {
      'nw',
      'vcb',
      'vcb-studio',
      'loli',
      'sakurato',
      'mabors',
      'ani',
      'dmhy',
      'ncar',
      'jsum',
    };
    if (commonPrefixes.contains(lower)) return true;
    return RegExp(r'^[A-Z0-9_-]+$').hasMatch(prefix);
  }

  static String _stripTrailingSequelNumber(String value) {
    final match = RegExp(r'^(.*?)[\s._\-]*(\d{1,2})$').firstMatch(value);
    if (match == null) return value;
    final prefix = match.group(1)?.trim() ?? '';
    if (prefix.length < 2 || RegExp(r'\d$').hasMatch(prefix)) {
      return value;
    }
    if (!RegExp(r'[A-Za-z\u4e00-\u9fff]').hasMatch(prefix)) {
      return value;
    }
    return prefix;
  }
}

class _CollectionDescriptor {
  const _CollectionDescriptor({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;

  factory _CollectionDescriptor.fromItem(
    LocalFileItem item,
    String rawTitle,
  ) {
    final season = item.episodeInfo?.seasonNumber ??
        _seasonFromText('${p.dirname(item.path)} $rawTitle ${item.name}');
    final source = '$rawTitle ${p.basename(p.dirname(item.path))} ${item.name}';
    final type = _typeFromText(source);
    if (type != null) {
      final seasonKey = season == null || season <= 0 ? '' : 's$season-';
      final seasonLabel = season == null || season <= 0
          ? ''
          : 'S${season.toString().padLeft(2, '0')} ';
      return _CollectionDescriptor(
        key: '$seasonKey${type.key}',
        label: '$seasonLabel${type.label}'.trim(),
      );
    }
    if (season != null && season > 0) {
      return _CollectionDescriptor(
        key: 's$season',
        label: 'S${season.toString().padLeft(2, '0')}',
      );
    }
    final sequel = _trailingSequelNumber(rawTitle);
    if (sequel != null) {
      return _CollectionDescriptor(key: 'sequel$sequel', label: '$sequel');
    }
    return const _CollectionDescriptor(key: 'main', label: '');
  }

  static int? _seasonFromText(String value) {
    final english = RegExp(
      r'\b(?:s|season)\s*0?(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(value);
    if (english != null) return int.tryParse(english.group(1)!);
    final chinese =
        RegExp(r'第\s*(\d{1,2})\s*季', unicode: true).firstMatch(value);
    return chinese == null ? null : int.tryParse(chinese.group(1)!);
  }

  static _CollectionType? _typeFromText(String value) {
    if (RegExp(r'剧场版|映画|电影版|\b(?:the\s+movie|movie)\b',
            caseSensitive: false, unicode: true)
        .hasMatch(value)) {
      return const _CollectionType('movie', '剧场版');
    }
    if (RegExp(r'\bova\b', caseSensitive: false).hasMatch(value)) {
      return const _CollectionType('ova', 'OVA');
    }
    if (RegExp(r'\boad\b', caseSensitive: false).hasMatch(value)) {
      return const _CollectionType('oad', 'OAD');
    }
    if (RegExp(r'番外篇|特别篇|总集篇|外传|\b(?:sp|special|lite)\b',
            caseSensitive: false, unicode: true)
        .hasMatch(value)) {
      return const _CollectionType('special', '特别篇');
    }
    return null;
  }

  static int? _trailingSequelNumber(String value) {
    final match = RegExp(r'[\s._\-]*(\d{1,2})$').firstMatch(value.trim());
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}

class _CollectionType {
  const _CollectionType(this.key, this.label);

  final String key;
  final String label;
}

class _NaturalNamePart {
  final String text;
  final int? number;

  const _NaturalNamePart({
    required this.text,
    required this.number,
  });

  factory _NaturalNamePart.from(String value) {
    return _NaturalNamePart(
      text: value.toLowerCase(),
      number: int.tryParse(value),
    );
  }

  int compareTo(_NaturalNamePart other) {
    final leftNumber = number;
    final rightNumber = other.number;
    if (leftNumber != null && rightNumber != null) {
      final cmp = leftNumber.compareTo(rightNumber);
      if (cmp != 0) return cmp;
      return text.length.compareTo(other.text.length);
    }
    return text.compareTo(other.text);
  }
}
