import 'package:kanyingyin/services/media_name_analyzer.dart';

enum MediaTechnicalBadgeKind { resolution, dolbyVision, hdr, dolbyAtmos }

class MediaTechnicalBadge {
  const MediaTechnicalBadge(this.label, this.kind);

  final String label;
  final MediaTechnicalBadgeKind kind;
}

class MediaTechnicalBadgeResolver {
  const MediaTechnicalBadgeResolver();

  List<MediaTechnicalBadge> resolve({
    required Iterable<String> names,
    String? resolution,
    int? videoWidth,
    int? videoHeight,
  }) {
    final sources =
        names.where((name) => name.trim().isNotEmpty).toList(growable: false);
    final parsed = sources
        .map(
          (name) => const MediaNameAnalyzer()
              .analyze(name, isDirectory: false)
              .releaseTags,
        )
        .toList(growable: false);
    final hasDimensions = videoWidth != null &&
        videoHeight != null &&
        videoWidth > 0 &&
        videoHeight > 0;
    final resolutionLabel = hasDimensions
        ? _fromDimensions(videoWidth, videoHeight)
        : _normalizeResolution(resolution) ??
            _bestResolution(parsed.map((tags) => tags.resolution));
    final combined = sources.join(' ');
    final dynamicRange = parsed.expand((tags) => tags.dynamicRange);
    final audio = parsed.expand((tags) => tags.audio);
    final hasDolbyVision = dynamicRange.any((value) => value == 'DV') ||
        RegExp(
          r'(?<![A-Za-z0-9])(?:DV|DoVi|Dolby[\s._-]*Vision)(?![A-Za-z0-9])',
          caseSensitive: false,
        ).hasMatch(combined);
    final hasHdr10Plus = RegExp(
      r'(?<![A-Za-z0-9])HDR10(?:\+|Plus)(?![A-Za-z0-9])',
      caseSensitive: false,
    ).hasMatch(combined);
    final hasHdr = !hasHdr10Plus &&
        (dynamicRange.any((value) => value == 'HDR') ||
            RegExp(
              r'(?<![A-Za-z0-9])HDR(?:10)?(?![A-Za-z0-9+])',
              caseSensitive: false,
            ).hasMatch(combined));
    final hasAtmos = audio.any((value) => value == 'Atmos') ||
        RegExp(
          r'(?<![A-Za-z0-9])(?:Dolby[\s._-]*)?Atmos(?![A-Za-z0-9])',
          caseSensitive: false,
        ).hasMatch(combined);
    return <MediaTechnicalBadge>[
      if (resolutionLabel != null)
        MediaTechnicalBadge(
          resolutionLabel,
          MediaTechnicalBadgeKind.resolution,
        ),
      if (hasDolbyVision)
        const MediaTechnicalBadge(
          '杜比视界',
          MediaTechnicalBadgeKind.dolbyVision,
        ),
      if (hasHdr10Plus)
        const MediaTechnicalBadge('HDR10+', MediaTechnicalBadgeKind.hdr),
      if (hasHdr) const MediaTechnicalBadge('HDR', MediaTechnicalBadgeKind.hdr),
      if (hasAtmos)
        const MediaTechnicalBadge(
          '杜比全景声',
          MediaTechnicalBadgeKind.dolbyAtmos,
        ),
    ];
  }

  List<MediaTechnicalBadge> aggregate(
    Iterable<List<MediaTechnicalBadge>> sources,
  ) {
    final all = sources.expand((items) => items).toList(growable: false);
    final resolution = all
        .where((item) => item.kind == MediaTechnicalBadgeKind.resolution)
        .fold<MediaTechnicalBadge?>(
          null,
          (best, item) => _rank(item.label) > _rank(best?.label) ? item : best,
        );
    final labels = <String>{};
    return <MediaTechnicalBadge>[
      if (resolution != null) resolution,
      for (final kind in const [
        MediaTechnicalBadgeKind.dolbyVision,
        MediaTechnicalBadgeKind.hdr,
        MediaTechnicalBadgeKind.dolbyAtmos,
      ])
        for (final item in all.where((item) => item.kind == kind))
          if (labels.add(item.label)) item,
    ];
  }

  String? _fromDimensions(int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    final long = width > height ? width : height;
    final short = width > height ? height : width;
    if (long >= 3840 && short >= 2160) return '4K';
    if (long >= 2560 && short >= 1440) return '2K';
    if (long >= 1920 && short >= 1080) return '1080P';
    return null;
  }

  String? _bestResolution(Iterable<String?> values) {
    String? result;
    for (final value in values) {
      final candidate = _normalizeResolution(value);
      if (_rank(candidate) > _rank(result)) result = candidate;
    }
    return result;
  }

  String? _normalizeResolution(String? value) {
    return switch (value?.trim().toLowerCase()) {
      '4k' || '2160p' => '4K',
      '2k' || '1440p' => '2K',
      '1080p' => '1080P',
      _ => null,
    };
  }

  int _rank(String? value) => switch (value) {
        '4K' => 3,
        '2K' => 2,
        '1080P' => 1,
        _ => 0,
      };
}
