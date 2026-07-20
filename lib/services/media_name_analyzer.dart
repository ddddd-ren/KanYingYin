import 'package:kanyingyin/modules/media/media_name_analysis.dart';

class MediaNameAnalyzer {
  const MediaNameAnalyzer();

  static final RegExp _advertisementPattern = RegExp(
    r'更多.*(?:资源|访问)|全网搜索|防走失|神秘入口|请访问|'
    r'(?:www\.|https?://)|(?:^|[\s._-])[\w-]+\.(?:vip|com|net)(?:$|[\s._-])',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _versionPattern = RegExp(
    r'导演剪辑版|加长版|重剪版|最终章|特别篇',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _seasonEpisodePattern = RegExp(
    r'\bS(\d{1,2})E(\d{1,3})(?:\s*[-~]\s*E?(\d{1,3}))?\b',
    caseSensitive: false,
  );
  static final RegExp _chineseSeasonEpisodePattern = RegExp(
    r'第\s*([零〇一二两三四五六七八九十\d]{1,3})\s*[季部]\s*'
    r'第\s*(\d{1,3})(?:\s*[-~至]\s*(\d{1,3}))?\s*[话話集]',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _seasonPattern = RegExp(
    r'(?:第\s*([零〇一二两三四五六七八九十\d]{1,3})\s*[季部]|'
    r'\bSeason\s*(\d{1,2})\b|\bS(\d{1,2})(?!E\d))',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _chineseEpisodePattern = RegExp(
    r'第\s*(\d{1,3})(?:\s*[-~至]\s*(\d{1,3}))?\s*[话話集]',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _englishEpisodePattern = RegExp(
    r'(?:^|[\s._-])(?:EP?|Episode)\s*(\d{1,3})(?!\d)',
    caseSensitive: false,
  );
  static final RegExp _bracketedEpisodePattern = RegExp(
    r'\[(\d{1,3})\]',
  );
  static final RegExp _standaloneEpisodePattern = RegExp(
    r'^(?:EP?|Episode)?\s*(\d{1,3})\s*$',
    caseSensitive: false,
  );
  static final RegExp _resolutionPattern = RegExp(
    r'\b(480p|720p|1080p|1440p|2160p|4K|8K)\b',
    caseSensitive: false,
  );
  static final RegExp _sourcePattern = RegExp(
    r'\b(WEB[\s._-]?DL|WEBRip|BDRip|BluRay|BD|TVRip|HDTV)\b',
    caseSensitive: false,
  );
  static final RegExp _codecPattern = RegExp(
    r'\b(x264|x265|H264|H265|HEVC|AVC|AV1)\b',
    caseSensitive: false,
  );
  static final RegExp _dvPattern = RegExp(
    r'\b(?:DV|Dolby[\s._-]*Vision)\b',
    caseSensitive: false,
  );
  static final RegExp _hdrPattern = RegExp(
    r'\bHDR(?:10\+?)?\b',
    caseSensitive: false,
  );
  static final RegExp _ddpPattern = RegExp(
    r'\b(?:DDP|EAC3)(?:[\s._-]*(\d(?:\.\d)?))?\b',
    caseSensitive: false,
  );
  static final RegExp _atmosPattern = RegExp(
    r'\bAtmos\b',
    caseSensitive: false,
  );
  static final RegExp _yearPattern = RegExp(
    r'(?:^|[\s._（(])((?:19|20)\d{2})(?=$|[\s._）)])',
  );
  static final RegExp _leadingReleaseGroupPattern = RegExp(
    r'^\[([^\]]{2,32})\]',
    unicode: true,
  );

  MediaNameAnalysis analyze(
    String name, {
    required bool isDirectory,
  }) {
    final baseName = isDirectory ? name.trim() : _withoutExtension(name);
    final normalized = _normalize(baseName);
    if (_advertisementPattern.hasMatch(normalized)) {
      return MediaNameAnalysis(
        originalName: name,
        role: MediaNodeRole.advertisement,
        confidence: 1,
        evidence: const <String>['advertisement-token'],
      );
    }

    final releaseTags = _releaseTags(normalized);
    final versionMatch = _versionPattern.firstMatch(normalized);
    final seasonEpisode = _seasonEpisodePattern.firstMatch(normalized);
    final chineseSeasonEpisode =
        _chineseSeasonEpisodePattern.firstMatch(normalized);
    final season = _seasonPattern.firstMatch(normalized);
    final chineseEpisode = _chineseEpisodePattern.firstMatch(normalized);
    final englishEpisode = _englishEpisodePattern.firstMatch(normalized);
    final bracketedEpisode = _bracketedEpisodePattern.firstMatch(normalized);
    final standaloneEpisode = _standaloneEpisodePattern.firstMatch(normalized);

    final seasonNumber = _firstPositive(<String?>[
      seasonEpisode?.group(1),
      chineseSeasonEpisode?.group(1),
      season?.group(1),
      season?.group(2),
      season?.group(3),
    ]);
    final episodeNumber = _firstPositive(<String?>[
      seasonEpisode?.group(2),
      chineseSeasonEpisode?.group(2),
      chineseEpisode?.group(1),
      englishEpisode?.group(1),
      bracketedEpisode?.group(1),
      standaloneEpisode?.group(1),
    ]);
    final episodeEndNumber = _firstPositive(<String?>[
      seasonEpisode?.group(3),
      chineseSeasonEpisode?.group(3),
      chineseEpisode?.group(2),
    ]);

    final role = versionMatch != null
        ? MediaNodeRole.version
        : episodeNumber != null
            ? MediaNodeRole.episode
            : seasonNumber != null
                ? MediaNodeRole.season
                : normalized.isEmpty
                    ? MediaNodeRole.unknown
                    : MediaNodeRole.work;
    final titleCandidates = _titleCandidates(
      normalized,
      role: role,
      releaseTags: releaseTags,
    );
    final evidence = <String>[
      if (versionMatch != null) _versionEvidence(versionMatch.group(0)!),
      if (seasonNumber != null) 'season-token',
      if (episodeNumber != null) 'episode-token',
      if (releaseTags.resolution != null) 'resolution-token',
      if (releaseTags.source != null) 'source-token',
      if (releaseTags.codec != null) 'codec-token',
    ];

    return MediaNameAnalysis(
      originalName: name,
      role: role,
      titleCandidates: titleCandidates,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeEndNumber: episodeEndNumber,
      year: _year(normalized),
      releaseTags: releaseTags,
      confidence: switch (role) {
        MediaNodeRole.advertisement => 1,
        MediaNodeRole.season ||
        MediaNodeRole.episode ||
        MediaNodeRole.version =>
          0.9,
        MediaNodeRole.work => 0.7,
        MediaNodeRole.unknown => 0,
      },
      evidence: evidence,
    );
  }

  String cleanReleaseTokens(String value) {
    return value
        .replaceAll(_resolutionPattern, ' ')
        .replaceAll(_sourcePattern, ' ')
        .replaceAll(_codecPattern, ' ')
        .replaceAll(_dvPattern, ' ')
        .replaceAll(_hdrPattern, ' ')
        .replaceAll(_ddpPattern, ' ')
        .replaceAll(_atmosPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _withoutExtension(String value) {
    return value.replaceFirst(RegExp(r'\.[^.\\/]+$'), '').trim();
  }

  String _normalize(String value) {
    return value
        .replaceAll(RegExp(r'[\u3000]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  MediaReleaseTags _releaseTags(String value) {
    final resolution = _resolutionPattern.firstMatch(value)?.group(1);
    final source = _sourcePattern.firstMatch(value)?.group(1);
    final codec = _codecPattern.firstMatch(value)?.group(1);
    final ddp = _ddpPattern.firstMatch(value);
    final releaseGroup = _releaseGroup(value);
    return MediaReleaseTags(
      resolution: _canonicalResolution(resolution),
      source: _canonicalSource(source),
      codec: codec?.toUpperCase(),
      dynamicRange: <String>[
        if (_dvPattern.hasMatch(value)) 'DV',
        if (_hdrPattern.hasMatch(value)) 'HDR',
      ],
      audio: <String>[
        if (ddp != null) ddp.group(1) == null ? 'DDP' : 'DDP ${ddp.group(1)}',
        if (_atmosPattern.hasMatch(value)) 'Atmos',
      ],
      releaseGroup: releaseGroup,
    );
  }

  String? _releaseGroup(String value) {
    final match = _leadingReleaseGroupPattern.firstMatch(value);
    final group = match?.group(1)?.trim();
    if (group == null || group.isEmpty) return null;
    if (_isReleaseNoise(group)) return null;
    return group;
  }

  List<String> _titleCandidates(
    String value, {
    required MediaNodeRole role,
    required MediaReleaseTags releaseTags,
  }) {
    final hasStructuralNoise = _hasStructuralNoise(value, releaseTags);
    if (!hasStructuralNoise && role == MediaNodeRole.work) {
      return <String>[value];
    }

    final candidates = <String>[];
    final quoted = RegExp(r'《([^》]+)》', unicode: true).firstMatch(value);
    if (quoted != null) {
      final candidate = _cleanTitle(quoted.group(1)!);
      if (candidate.isNotEmpty) candidates.add(candidate);
    }
    final cleaned = _cleanTitle(value);
    if (cleaned.isNotEmpty && !candidates.contains(cleaned)) {
      candidates.add(cleaned);
    }
    return candidates;
  }

  bool _hasStructuralNoise(String value, MediaReleaseTags tags) {
    return _seasonEpisodePattern.hasMatch(value) ||
        _chineseSeasonEpisodePattern.hasMatch(value) ||
        _seasonPattern.hasMatch(value) ||
        _chineseEpisodePattern.hasMatch(value) ||
        _englishEpisodePattern.hasMatch(value) ||
        _bracketedEpisodePattern.hasMatch(value) ||
        _standaloneEpisodePattern.hasMatch(value) ||
        _versionPattern.hasMatch(value) ||
        tags.resolution != null ||
        tags.source != null ||
        tags.codec != null ||
        tags.dynamicRange.isNotEmpty ||
        tags.audio.isNotEmpty ||
        RegExp(r'^\d{4,}[\s._-]+').hasMatch(value) ||
        RegExp(r'全\s*\d+\s*集|全集|内附', unicode: true).hasMatch(value) ||
        (_year(value) != null && !RegExp(r'^\d{4}$').hasMatch(value));
  }

  String _cleanTitle(String value) {
    var result = cleanReleaseTokens(value)
        .replaceFirst(RegExp(r'^\d{4,}[\s._-]+'), '')
        .replaceAll(_seasonEpisodePattern, ' ')
        .replaceAll(_chineseSeasonEpisodePattern, ' ')
        .replaceAll(_seasonPattern, ' ')
        .replaceAll(_chineseEpisodePattern, ' ')
        .replaceAll(_englishEpisodePattern, ' ')
        .replaceAll(_bracketedEpisodePattern, ' ')
        .replaceAll(_standaloneEpisodePattern, ' ')
        .replaceAll(_versionPattern, ' ')
        .replaceAll(RegExp(r'[（(](?:19|20)\d{2}[)）]'), ' ')
        .replaceAll(RegExp(r'全\s*\d+\s*集|全集|完结'), ' ')
        .replaceAll(RegExp(r'内附.*$', unicode: true), ' ')
        .replaceAll(_leadingReleaseGroupPattern, ' ')
        .replaceAll(RegExp(r'[《》【】\[\]]', unicode: true), ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'^[\s&+,\-–—:：]+|[\s&+,\-–—:：]+$'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (result != '1923') {
      result = result.replaceAll(_yearPattern, ' ').replaceAll(
            RegExp(r'\s+'),
            ' ',
          );
    }
    return result.trim();
  }

  int? _year(String value) {
    if (RegExp(r'^\d{4}$').hasMatch(value)) return null;
    final match = _yearPattern.firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int? _firstPositive(List<String?> values) {
    for (final value in values) {
      if (value == null || value.isEmpty) continue;
      final number = _parseNumber(value);
      if (number != null && number > 0) return number;
    }
    return null;
  }

  int? _parseNumber(String value) {
    final arabic = int.tryParse(value);
    if (arabic != null) return arabic;
    const digits = <String, int>{
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (!value.contains('十')) return digits[value];
    final parts = value.split('十');
    if (parts.length != 2) return null;
    final tens = parts.first.isEmpty ? 1 : digits[parts.first];
    final ones = parts.last.isEmpty ? 0 : digits[parts.last];
    if (tens == null || ones == null) return null;
    final result = tens * 10 + ones;
    return result >= 1 && result <= 99 ? result : null;
  }

  bool _isReleaseNoise(String value) {
    return _resolutionPattern.hasMatch(value) ||
        _sourcePattern.hasMatch(value) ||
        _codecPattern.hasMatch(value);
  }

  String? _canonicalResolution(String? value) {
    if (value == null) return null;
    final lower = value.toLowerCase();
    return lower == '4k' || lower == '8k' ? lower.toUpperCase() : lower;
  }

  String? _canonicalSource(String? value) {
    if (value == null) return null;
    return switch (value.toLowerCase().replaceAll(RegExp(r'[\s._]'), '-')) {
      'web-dl' => 'Web-DL',
      'webrip' => 'WEBRip',
      'bdrip' => 'BDRip',
      'bluray' => 'BluRay',
      'bd' => 'BD',
      'tvrip' => 'TVRip',
      'hdtv' => 'HDTV',
      _ => value,
    };
  }

  String _versionEvidence(String value) {
    if (value.contains('导演剪辑版')) return 'director-cut';
    if (value.contains('加长版')) return 'extended-cut';
    if (value.contains('重剪版')) return 'recut';
    if (value.contains('特别篇')) return 'special';
    return 'version';
  }
}
