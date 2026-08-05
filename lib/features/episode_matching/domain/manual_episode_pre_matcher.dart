import 'package:path/path.dart' as p;

final class ManualEpisodePreMatch {
  const ManualEpisodePreMatch({
    required this.seasonNumber,
    required this.episodeNumber,
  });

  final int seasonNumber;
  final int episodeNumber;

  @override
  bool operator ==(Object other) {
    return other is ManualEpisodePreMatch &&
        other.seasonNumber == seasonNumber &&
        other.episodeNumber == episodeNumber;
  }

  @override
  int get hashCode => Object.hash(seasonNumber, episodeNumber);
}

final class ManualEpisodePreMatcher {
  const ManualEpisodePreMatcher();

  static final RegExp _seasonEpisodePattern = RegExp(
    r'(?<![A-Za-z0-9])S(?<season>\d{1,2})[ ._-]*E(?<episode>\d{1,3})(?!\d)',
    caseSensitive: false,
  );
  static final RegExp _chineseSeasonEpisodePattern = RegExp(
    r'第\s*(?<season>\d{1,2})\s*[季部]\s*第?\s*(?<episode>\d{1,3})\s*[集话話]',
    unicode: true,
  );
  static final RegExp _explicitEpisodePattern = RegExp(
    r'(?<![A-Za-z0-9])(?:EP|Episode|E)\s*(?<episode>\d{1,3})(?!\d)',
    caseSensitive: false,
  );
  static final RegExp _seasonDirectoryPattern = RegExp(
    r'(?:^|[ ._-])(?:Season|S)\s*(?<english>\d{1,2})(?:$|[ ._-])|第\s*(?<chinese>\d{1,2})\s*[季部]',
    caseSensitive: false,
    unicode: true,
  );
  static final Set<String> _genericDirectoryNames = <String>{
    'tv',
    'video',
    'videos',
    '电视剧',
    '剧集',
    '电视',
    '媒体库',
  };

  ManualEpisodePreMatch? match({
    required String originalName,
    required String parentName,
    required String expectedSeriesName,
    String? grandParentName,
    int? selectedSeasonNumber,
  }) {
    final fileName = p.basenameWithoutExtension(originalName);
    final directorySeason = _seasonFromDirectory(parentName);
    final identityName = directorySeason == null ? parentName : grandParentName;
    if (!_hasReliableIdentity(
      identityName: identityName,
      expectedSeriesName: expectedSeriesName,
    )) {
      return null;
    }

    final combined = _seasonEpisodePattern.firstMatch(fileName) ??
        _chineseSeasonEpisodePattern.firstMatch(fileName);
    if (combined != null) {
      final seasonNumber = _readInt(combined, 'season');
      final episodeNumber = _readInt(combined, 'episode');
      if (!_positive(seasonNumber) || !_positive(episodeNumber)) return null;
      if (directorySeason != null && directorySeason != seasonNumber) {
        return null;
      }
      return ManualEpisodePreMatch(
        seasonNumber: seasonNumber!,
        episodeNumber: episodeNumber!,
      );
    }

    final episodeMatch = _explicitEpisodePattern.firstMatch(fileName);
    if (episodeMatch == null) return null;
    final episodeNumber = _readInt(episodeMatch, 'episode');
    final seasonNumber = directorySeason ?? selectedSeasonNumber;
    if (!_positive(seasonNumber) || !_positive(episodeNumber)) return null;
    return ManualEpisodePreMatch(
      seasonNumber: seasonNumber!,
      episodeNumber: episodeNumber!,
    );
  }

  int? _seasonFromDirectory(String value) {
    final match = _seasonDirectoryPattern.firstMatch(value.trim());
    if (match == null) return null;
    return int.tryParse(
      match.namedGroup('english') ?? match.namedGroup('chinese') ?? '',
    );
  }

  bool _hasReliableIdentity({
    required String? identityName,
    required String expectedSeriesName,
  }) {
    final identity = _normalize(identityName ?? '');
    final expected = _normalize(expectedSeriesName);
    if (identity.isEmpty || expected.isEmpty) return false;
    if (_genericDirectoryNames.contains(identity)) return false;
    return identity == expected ||
        identity.contains(expected) ||
        expected.contains(identity);
  }

  String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s._\-\[\]()（）【】]+', unicode: true), '');
  }

  int? _readInt(RegExpMatch match, String name) {
    return int.tryParse(match.namedGroup(name) ?? '');
  }

  bool _positive(int? value) => value != null && value > 0;
}
