import 'dart:io';

import 'package:kanyingyin/modules/local/local_file_item.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_subtitle_matcher.dart';
import 'package:kanyingyin/services/local_cover_finder.dart';
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
    int minRecognizedVideoSizeBytes =
        LocalVideoFileTypes.minRecognizedVideoSizeBytes,
    int Function()? minRecognizedVideoSizeBytesProvider,
  })  : _episodeParser = episodeParser ?? LocalEpisodeParser(),
        _subtitleMatcher = subtitleMatcher ?? LocalSubtitleMatcher(),
        _coverFinder = coverFinder ?? LocalCoverFinder(),
        _minRecognizedVideoSizeBytesProvider =
            minRecognizedVideoSizeBytesProvider ??
                (() => minRecognizedVideoSizeBytes);

  final LocalEpisodeParser _episodeParser;
  final LocalSubtitleMatcher _subtitleMatcher;
  final LocalCoverFinder _coverFinder;
  final int Function() _minRecognizedVideoSizeBytesProvider;

  @override
  Future<LocalScanResult> scan(
    String path, {
    required LocalSortMode sortMode,
    required bool ascending,
  }) async {
    final minSizeBytes = _minRecognizedVideoSizeBytesProvider();
    final items = <LocalFileItem>[];
    var skippedCount = 0;

    Future<void> collectDirectory(Directory directory) async {
      await for (final entry in directory.list(followLinks: false)) {
        try {
          final name = p.basename(entry.path);
          if (name.startsWith('.')) {
            skippedCount++;
            continue;
          }

          if (entry is Directory) {
            if (LocalVideoFileTypes.isWindowsSystemDirectory(name)) {
              skippedCount++;
              continue;
            }
            await collectDirectory(entry);
            continue;
          }

          if (entry is! File) {
            skippedCount++;
            continue;
          }

          final stat = await entry.stat();
          if (!LocalVideoFileTypes.isRecognizedVideo(
            name,
            size: stat.size,
            minSizeBytes: minSizeBytes,
          )) {
            skippedCount++;
            continue;
          }
          items.add(LocalFileItem(
            path: entry.path,
            name: name,
            size: stat.size,
            modified: stat.modified,
            isDirectory: false,
            isVideo: true,
            cover: _coverFinder.findVideoCover(entry.path),
            subtitlePath: _subtitleMatcher.findForVideo(entry.path),
            episodeInfo: _episodeParser.parse(entry.path),
          ));
        } catch (e) {
          skippedCount++;
          AppLogger().w('LocalMediaScanner: skip entry ${entry.path}: $e');
        }
      }
    }

    try {
      await collectDirectory(Directory(path));
    } catch (e) {
      skippedCount++;
      AppLogger().w('LocalMediaScanner: skip directory $path: $e');
    }

    items.sort((a, b) => _compareItems(a, b, sortMode, ascending));
    return LocalScanResult(
      currentPath: path,
      items: items,
      skippedCount: skippedCount,
    );
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
