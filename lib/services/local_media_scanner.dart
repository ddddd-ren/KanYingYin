import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/modules/local/media_location.dart';
import 'package:kanyingyin/services/file_system_media_entry_provider.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
import 'package:kanyingyin/services/local_media_entry_provider.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/utils/logger.dart';
import 'package:path/path.dart' as p;

abstract class ILocalMediaScanner {
  Future<LocalScanResult> scan(
    String path, {
    required LocalSortMode sortMode,
    required bool ascending,
  });
}

class LocalMediaScanner implements ILocalMediaScanner {
  LocalMediaScanner({
    LocalEpisodeParser? episodeParser,
    LocalSubtitleMatcher? subtitleMatcher,
    LocalCoverFinder? coverFinder,
    List<LocalMediaEntryProvider>? entryProviders,
    int minRecognizedVideoSizeBytes =
        LocalVideoFileTypes.minRecognizedVideoSizeBytes,
    int Function()? minRecognizedVideoSizeBytesProvider,
  })  : _episodeParser = episodeParser ?? LocalEpisodeParser(),
        _subtitleMatcher = subtitleMatcher ?? LocalSubtitleMatcher(),
        _coverFinder = coverFinder ?? LocalCoverFinder(),
        _entryProviders = entryProviders ??
            const <LocalMediaEntryProvider>[
              FileSystemMediaEntryProvider(),
            ],
        _minRecognizedVideoSizeBytesProvider =
            minRecognizedVideoSizeBytesProvider ??
                (() => minRecognizedVideoSizeBytes);

  final LocalEpisodeParser _episodeParser;
  final LocalSubtitleMatcher _subtitleMatcher;
  final LocalCoverFinder _coverFinder;
  final List<LocalMediaEntryProvider> _entryProviders;
  final int Function() _minRecognizedVideoSizeBytesProvider;

  @override
  Future<LocalScanResult> scan(
    String path, {
    required LocalSortMode sortMode,
    required bool ascending,
  }) async {
    return scanLocation(
      MediaLocation.file(path),
      sortMode: sortMode,
      ascending: ascending,
    );
  }

  Future<LocalScanResult> scanLocation(
    MediaLocation location, {
    required LocalSortMode sortMode,
    required bool ascending,
  }) async {
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    final items = <LocalFileItem>[];
    var skippedCount = 0;
    final provider = _providerFor(location);

    Future<void> collectDirectory(
      MediaLocation directory,
      String logicalDirectory,
    ) async {
      final entries = await provider.listChildren(directory);
      for (final entry in entries) {
        try {
          final name = entry.name;
          if (name.startsWith('.')) {
            skippedCount++;
            continue;
          }

          if (entry.isDirectory) {
            if (LocalVideoFileTypes.isWindowsSystemDirectory(name)) {
              skippedCount++;
              continue;
            }
            await collectDirectory(
              entry.location,
              p.join(logicalDirectory, name),
            );
            continue;
          }

          if (!LocalVideoFileTypes.isRecognizedVideo(
            name,
            size: entry.size,
            minSizeBytes: minSizeBytes,
          )) {
            skippedCount++;
            continue;
          }
          final displayPath = entry.location.isFile
              ? entry.location.value
              : p.join(logicalDirectory, name);
          items.add(LocalFileItem(
            location: entry.location,
            name: name,
            size: entry.size,
            modified: entry.modified,
            isDirectory: false,
            isVideo: true,
            cover: entry.location.isFile
                ? _coverFinder.findVideoCover(entry.location.value)
                : null,
            subtitlePath: entry.location.isFile
                ? await _subtitleMatcher.findForVideo(entry.location.value)
                : null,
            episodeInfo: _episodeParser.parse(displayPath),
          ));
        } catch (e) {
          skippedCount++;
          AppLogger().w(
            'LocalMediaScanner: skip entry ${entry.location.value}: $e',
          );
        }
      }
    }

    try {
      if (!await provider.canAccess(location)) {
        throw StateError('媒体位置不可访问');
      }
      await collectDirectory(location, '');
    } catch (e) {
      skippedCount++;
      AppLogger().w(
        'LocalMediaScanner: skip directory ${location.value}: $e',
      );
    }

    items.sort((a, b) => _compareItems(a, b, sortMode, ascending));
    return LocalScanResult(
      currentPath: location.value,
      items: items,
      skippedCount: skippedCount,
    );
  }

  LocalMediaEntryProvider _providerFor(MediaLocation location) {
    for (final provider in _entryProviders) {
      if (provider.supports(location)) return provider;
    }
    throw UnsupportedError('没有可用于该媒体位置的扫描器: ${location.kind.name}');
  }

  int _compareItems(
    LocalFileItem a,
    LocalFileItem b,
    LocalSortMode sortMode,
    bool ascending,
  ) {
    if (a.isDirectory && !b.isDirectory) return -1;
    if (!a.isDirectory && b.isDirectory) return 1;

    final cmp = switch (sortMode) {
      LocalSortMode.size => a.size.compareTo(b.size),
      LocalSortMode.modified => a.modified.compareTo(b.modified),
      LocalSortMode.name => _compareNaturalName(a.name, b.name),
    };
    return ascending ? cmp : -cmp;
  }

  int _compareNaturalName(String left, String right) {
    final leftParts = _splitNaturalParts(left);
    final rightParts = _splitNaturalParts(right);
    final length = leftParts.length < rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < length; i++) {
      final leftPart = leftParts[i];
      final rightPart = rightParts[i];
      final cmp = leftPart.compareTo(rightPart);
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
