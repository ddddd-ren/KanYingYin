import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_tree.dart';
import 'package:kanyingyin/modules/media/media_name_analysis.dart';
import 'package:kanyingyin/services/cloud/cloud_series_identity_resolver.dart';
import 'package:kanyingyin/services/local_episode_parser.dart';
import 'package:kanyingyin/services/local_video_file_types.dart';
import 'package:kanyingyin/services/media_name_analyzer.dart';
import 'package:path/path.dart' as p;

class CloudMediaTreeResolver {
  const CloudMediaTreeResolver({
    this.nameAnalyzer = const MediaNameAnalyzer(),
  });

  final MediaNameAnalyzer nameAnalyzer;

  CloudMediaTree resolve({
    required String sourceId,
    required List<String> configuredRoots,
    required Map<String, List<CloudFileEntry>> directoryEntries,
    required int minSizeBytes,
  }) {
    final normalizedSourceId = sourceId.trim();
    if (normalizedSourceId.isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId', '来源标识不能为空');
    }
    final context = _ResolutionContext(
      sourceId: normalizedSourceId,
      directoryEntries: <String, List<CloudFileEntry>>{
        for (final entry in directoryEntries.entries)
          CloudSeriesIdentityResolver.normalizeRemotePath(entry.key):
              entry.value,
      },
      minSizeBytes: minSizeBytes,
      nameAnalyzer: nameAnalyzer,
      episodeParser: LocalEpisodeParser(nameAnalyzer: nameAnalyzer),
    );
    final roots = configuredRoots
        .map(CloudSeriesIdentityResolver.normalizeRemotePath)
        .toSet()
        .toList()
      ..sort((first, second) => first.length.compareTo(second.length));
    final canonicalRoots = <String>[];
    for (final root in roots) {
      final isNested = canonicalRoots.any(
        (parent) =>
            root == parent || parent == '/' || root.startsWith('$parent/'),
      );
      if (!isNested) canonicalRoots.add(root);
    }
    for (final root in canonicalRoots) {
      context.discoverConfiguredRoot(root);
    }
    return context.build();
  }
}

class _ResolutionContext {
  _ResolutionContext({
    required this.sourceId,
    required this.directoryEntries,
    required this.minSizeBytes,
    required this.nameAnalyzer,
    required this.episodeParser,
  });

  final String sourceId;
  final Map<String, List<CloudFileEntry>> directoryEntries;
  final int minSizeBytes;
  final MediaNameAnalyzer nameAnalyzer;
  final LocalEpisodeParser episodeParser;
  final List<CloudWorkIdentity> _works = <CloudWorkIdentity>[];
  final List<CloudFileEntry> _ignored = <CloudFileEntry>[];
  final List<CloudMediaTreeConflict> _conflicts = <CloudMediaTreeConflict>[];
  final Set<String> _visitedDirectories = <String>{};
  final Set<String> _resolvedWorkRoots = <String>{};
  final Set<String> _ignoredKeys = <String>{};

  static final RegExp _trailingEpisodePattern = RegExp(
    r'^(.*?)[\s._-]+(\d{1,3})$',
    unicode: true,
  );
  static final RegExp _leadingEpisodePattern = RegExp(
    r'^(\d{1,3})[\s._-]+\S',
    unicode: true,
  );

  void discoverConfiguredRoot(String directoryPath) {
    final directoryName = p.posix.basename(directoryPath);
    final directoryAnalysis = nameAnalyzer.analyze(
      directoryName,
      isDirectory: true,
    );
    final excludesConfiguredRootTitle =
        directoryAnalysis.role == MediaNodeRole.advertisement;
    final isStructuralRoot =
        nameAnalyzer.isTransparentDirectoryName(directoryName) ||
            directoryAnalysis.role == MediaNodeRole.season;
    final containsOnlyEpisodeVideos = _containsOnlyEpisodeVideos(
      directoryPath,
    );
    final containsOnlyStructuralDirectories =
        _containsOnlyStructuralDirectories(directoryPath);
    if ((isStructuralRoot ||
            containsOnlyEpisodeVideos ||
            containsOnlyStructuralDirectories) &&
        _containsRecognizedVideo(directoryPath, <String>{})) {
      final workName = isStructuralRoot
          ? _nearestWorkName(directoryPath)
          : directoryName.trim();
      if (workName != null && workName.isNotEmpty) {
        _resolveDirectoryWork(
          CloudFileEntry(
            id: '',
            remotePath: directoryPath,
            name: workName,
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
          configuredSeasonNumber: directoryAnalysis.seasonNumber,
          configuredReleaseTags: directoryAnalysis.releaseTags,
          configuredYear: directoryAnalysis.year,
          configuredDirectoryName: directoryName,
          includeRootTitleCandidates: !excludesConfiguredRootTitle,
        );
        return;
      }
    }
    discover(directoryPath);
  }

  bool _containsOnlyEpisodeVideos(String directoryPath) {
    final videos = (directoryEntries[directoryPath] ?? const <CloudFileEntry>[])
        .where((entry) => !entry.isDirectory && _isRecognizedVideo(entry))
        .toList(growable: false);
    return videos.isNotEmpty && videos.every(_hasEpisodeEvidence);
  }

  bool _containsOnlyStructuralDirectories(String directoryPath) {
    final entries = directoryEntries[directoryPath] ?? const <CloudFileEntry>[];
    if (entries.any(
      (entry) => !entry.isDirectory && _isRecognizedVideo(entry),
    )) {
      return false;
    }
    final contentDirectories = entries
        .where(
          (entry) =>
              entry.isDirectory &&
              _containsRecognizedVideo(_pathOf(entry), <String>{}),
        )
        .toList(growable: false);
    return contentDirectories.isNotEmpty &&
        contentDirectories.every((entry) {
          final analysis = nameAnalyzer.analyze(
            entry.name,
            isDirectory: true,
          );
          final isStructuralDirectory = analysis.role == MediaNodeRole.season ||
              nameAnalyzer.isTransparentDirectoryName(entry.name);
          return isStructuralDirectory &&
              _containsOnlyEpisodeVideosRecursively(
                _pathOf(entry),
                <String>{},
              );
        });
  }

  bool _containsOnlyEpisodeVideosRecursively(
    String directoryPath,
    Set<String> visited,
  ) {
    if (!visited.add(directoryPath)) return false;
    var foundVideo = false;
    final entries = directoryEntries[directoryPath] ?? const <CloudFileEntry>[];
    for (final entry in entries) {
      if (entry.isDirectory) {
        final childPath = _pathOf(entry);
        if (!_containsRecognizedVideo(childPath, <String>{})) continue;
        if (!_containsOnlyEpisodeVideosRecursively(
          childPath,
          visited,
        )) {
          return false;
        }
        foundVideo = true;
        continue;
      }
      if (!_isRecognizedVideo(entry)) continue;
      foundVideo = true;
      if (!_hasEpisodeEvidence(entry)) return false;
    }
    return foundVideo;
  }

  void discover(String directoryPath) {
    if (!_visitedDirectories.add(directoryPath)) return;
    final entries = directoryEntries[directoryPath] ?? const <CloudFileEntry>[];
    final directVideos = <CloudFileEntry>[];
    for (final entry in entries) {
      final analysis = nameAnalyzer.analyze(
        entry.name,
        isDirectory: entry.isDirectory,
      );
      if (_shouldIgnoreAdvertisement(entry, analysis)) {
        _ignoreTree(entry);
        continue;
      }
      if (entry.isDirectory) {
        final path = _pathOf(entry);
        if (_isWorkRoot(path)) {
          _resolveDirectoryWork(
            entry,
            includeRootTitleCandidates:
                analysis.role != MediaNodeRole.advertisement,
          );
        } else {
          discover(path);
        }
        continue;
      }
      if (_isRecognizedVideo(entry)) {
        directVideos.add(entry);
      } else {
        _ignore(entry);
      }
    }
    final promotedPaths = _resolveFlatEpisodeWorks(
      directoryPath,
      directVideos,
    );
    for (final video in directVideos) {
      if (!promotedPaths.contains(_pathOf(video))) {
        _resolveStandaloneFile(video);
      }
    }
  }

  _FlatEpisodeCandidate? _episodeCandidate(CloudFileEntry entry) {
    final analysis = nameAnalyzer.analyze(entry.name, isDirectory: false);
    final parsed = episodeParser.parse(entry.name);
    final episodeNumber = analysis.episodeNumber ?? parsed?.episodeNumber;
    if (episodeNumber == null || episodeNumber <= 0) return null;
    final titles = <String>[];
    final parsedTitle = parsed?.seriesName.trim();
    if (parsedTitle != null && parsedTitle.isNotEmpty) {
      _addUnique(titles, parsedTitle);
    }
    for (final candidate in analysis.titleCandidates) {
      _addUnique(titles, candidate);
    }
    if (titles.isEmpty) return null;
    return _FlatEpisodeCandidate(
      entry: entry,
      seriesName: titles.first,
      titleCandidates: titles,
      seasonNumber: analysis.seasonNumber ?? parsed?.seasonNumber ?? 1,
      episodeNumber: episodeNumber,
      releaseTags: analysis.releaseTags,
      strongEvidence: analysis.episodeNumber != null,
    );
  }

  bool _hasEpisodeEvidence(CloudFileEntry entry) {
    final analysis = nameAnalyzer.analyze(entry.name, isDirectory: false);
    return analysis.episodeNumber != null ||
        episodeParser.parse(entry.name)?.episodeNumber != null;
  }

  Set<String> _resolveFlatEpisodeWorks(
    String directoryPath,
    List<CloudFileEntry> videos,
  ) {
    final groups = <String, List<_FlatEpisodeCandidate>>{};
    for (final video in videos) {
      final candidate =
          _episodeCandidate(video) ?? _trailingEpisodeCandidate(video);
      if (candidate == null) continue;
      final identity = CloudSeriesIdentityResolver.normalizeSeriesName(
        candidate.seriesName,
      );
      if (identity.isEmpty) continue;
      groups.putIfAbsent(identity, () => <_FlatEpisodeCandidate>[]).add(
            candidate,
          );
    }
    final promoted = <String>{};
    for (final groupEntry in groups.entries) {
      final candidates = groupEntry.value;
      final distinctEpisodes =
          candidates.map((candidate) => candidate.episodeNumber).toSet().length;
      final hasStrongEvidence = candidates.any(
        (candidate) => candidate.strongEvidence,
      );
      if (!hasStrongEvidence && distinctEpisodes < 2) continue;

      final digest = sha256
          .convert(
            utf8.encode('$sourceId|$directoryPath|${groupEntry.key}'),
          )
          .toString();
      final rootId = 'flat-${digest.substring(0, 24)}';
      final workKey = '$sourceId|work|$rootId';
      final titleCandidates = <String>[];
      for (final candidate in candidates) {
        for (final title in candidate.titleCandidates) {
          _addUnique(titleCandidates, title);
        }
      }
      final displayTitle = titleCandidates.first;
      final seasons = <int, List<_FlatEpisodeCandidate>>{};
      for (final candidate in candidates) {
        seasons
            .putIfAbsent(
              candidate.seasonNumber,
              () => <_FlatEpisodeCandidate>[],
            )
            .add(candidate);
        final path = _pathOf(candidate.entry);
        promoted.add(path);
        _resolvedWorkRoots.add(path);
      }
      final seasonNumbers = seasons.keys.toList(growable: false)..sort();
      _works.add(
        CloudWorkIdentity(
          sourceId: sourceId,
          workKey: workKey,
          root: CloudFileEntry(
            id: rootId,
            remotePath: directoryPath,
            name: displayTitle,
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
          remoteName: displayTitle,
          displayTitle: displayTitle,
          titleCandidates: List<String>.unmodifiable(titleCandidates),
          seasons: <CloudSeasonIdentity>[
            for (final seasonNumber in seasonNumbers)
              _flatSeason(
                workKey: workKey,
                displayTitle: displayTitle,
                seasonNumber: seasonNumber,
                candidates: seasons[seasonNumber]!,
              ),
          ],
        ),
      );
    }
    return promoted;
  }

  _FlatEpisodeCandidate? _trailingEpisodeCandidate(CloudFileEntry entry) {
    final baseName = p.basenameWithoutExtension(entry.name).trim();
    final match = _trailingEpisodePattern.firstMatch(baseName);
    if (match == null) return null;
    final episodeNumber = int.tryParse(match.group(2)!);
    if (episodeNumber == null || episodeNumber <= 0) return null;
    final prefix = match.group(1)!.trim();
    final analysis = nameAnalyzer.analyze('$prefix.mkv', isDirectory: false);
    final tags = analysis.releaseTags;
    final hasReleaseEvidence = tags.releaseGroup != null ||
        tags.resolution != null ||
        tags.source != null ||
        tags.codec != null;
    if (!hasReleaseEvidence || analysis.titleCandidates.isEmpty) return null;
    return _FlatEpisodeCandidate(
      entry: entry,
      seriesName: analysis.titleCandidates.first,
      titleCandidates: List<String>.from(analysis.titleCandidates),
      seasonNumber: 1,
      episodeNumber: episodeNumber,
      releaseTags: tags,
      strongEvidence: false,
    );
  }

  CloudSeasonIdentity _flatSeason({
    required String workKey,
    required String displayTitle,
    required int seasonNumber,
    required List<_FlatEpisodeCandidate> candidates,
  }) {
    candidates.sort((first, second) {
      final episode = first.episodeNumber.compareTo(second.episodeNumber);
      return episode != 0
          ? episode
          : first.entry.remotePath.compareTo(second.entry.remotePath);
    });
    return CloudSeasonIdentity(
      workKey: workKey,
      seasonNumber: seasonNumber,
      displayName: '$displayTitle 第 $seasonNumber 季',
      remoteDirectories: const <CloudFileEntry>[],
      episodes: <CloudEpisodeIdentity>[
        for (final candidate in candidates)
          CloudEpisodeIdentity(
            entry: candidate.entry,
            remoteName: candidate.entry.name,
            displayName: _episodeDisplayName(
              displayTitle,
              seasonNumber,
              candidate.episodeNumber,
              candidate.entry.name,
            ),
            seasonNumber: seasonNumber,
            episodeNumber: candidate.episodeNumber,
            releaseTags: candidate.releaseTags,
          ),
      ],
    );
  }

  CloudMediaTree build() {
    _works.sort((first, second) {
      final path = first.root.remotePath.compareTo(second.root.remotePath);
      return path != 0 ? path : first.workKey.compareTo(second.workKey);
    });
    return CloudMediaTree(
      sourceId: sourceId,
      works: List<CloudWorkIdentity>.unmodifiable(_works),
      ignored: List<CloudFileEntry>.unmodifiable(_ignored),
      conflicts: List<CloudMediaTreeConflict>.unmodifiable(_conflicts),
    );
  }

  bool _isWorkRoot(String directoryPath) {
    final entries = directoryEntries[directoryPath] ?? const <CloudFileEntry>[];
    for (final entry in entries) {
      final analysis = nameAnalyzer.analyze(
        entry.name,
        isDirectory: entry.isDirectory,
      );
      if (_shouldIgnoreAdvertisement(entry, analysis)) continue;
      if (!entry.isDirectory && _isRecognizedVideo(entry)) return true;
      if (entry.isDirectory &&
          analysis.role == MediaNodeRole.season &&
          analysis.seasonNumber != null &&
          _containsRecognizedVideo(_pathOf(entry), <String>{})) {
        return true;
      }
      if (entry.isDirectory &&
          nameAnalyzer.isTransparentDirectoryName(entry.name) &&
          _containsRecognizedVideo(_pathOf(entry), <String>{})) {
        return true;
      }
    }
    return false;
  }

  bool _containsRecognizedVideo(String directoryPath, Set<String> visited) {
    if (!visited.add(directoryPath)) return false;
    final entries = directoryEntries[directoryPath] ?? const <CloudFileEntry>[];
    for (final entry in entries) {
      final analysis = nameAnalyzer.analyze(
        entry.name,
        isDirectory: entry.isDirectory,
      );
      if (analysis.role == MediaNodeRole.advertisement && !entry.isDirectory) {
        continue;
      }
      if (!entry.isDirectory && _isRecognizedVideo(entry)) return true;
      if (entry.isDirectory &&
          _containsRecognizedVideo(_pathOf(entry), visited)) {
        return true;
      }
    }
    return false;
  }

  void _resolveDirectoryWork(
    CloudFileEntry root, {
    int? configuredSeasonNumber,
    MediaReleaseTags configuredReleaseTags = const MediaReleaseTags(),
    int? configuredYear,
    String? configuredDirectoryName,
    bool includeRootTitleCandidates = true,
  }) {
    final rootPath = _pathOf(root);
    if (!_resolvedWorkRoots.add(rootPath)) return;
    final rootAnalysis = nameAnalyzer.analyze(root.name, isDirectory: true);
    final workKey = workKeyFor(sourceId, root);
    final builders = <int, _SeasonBuilder>{};
    final standaloneVideos = <CloudFileEntry>[];
    final standaloneReleaseTags = <String, MediaReleaseTags>{};
    final transparentDirectories = <CloudFileEntry>[];
    final aliases = <String>[];
    final entries = directoryEntries[rootPath] ?? const <CloudFileEntry>[];
    if (configuredSeasonNumber != null) {
      final builder = builders.putIfAbsent(
        configuredSeasonNumber,
        _SeasonBuilder.new,
      );
      builder
        ..directories.add(
          CloudFileEntry(
            id: root.id,
            remotePath: root.remotePath,
            name: configuredDirectoryName ?? root.name,
            size: 0,
            modifiedAt: null,
            isDirectory: true,
          ),
        )
        ..year = configuredYear;
      _collectSeasonEpisodes(
        directoryPath: rootPath,
        folderSeasonNumber: configuredSeasonNumber,
        inheritedReleaseTags: configuredReleaseTags,
        episodes: builder.episodes,
        aliases: aliases,
        visited: <String>{},
      );
    } else {
      for (final entry in entries) {
        final analysis = nameAnalyzer.analyze(
          entry.name,
          isDirectory: entry.isDirectory,
        );
        if (_shouldIgnoreAdvertisement(entry, analysis)) {
          _ignoreTree(entry);
          continue;
        }
        if (entry.isDirectory &&
            analysis.role == MediaNodeRole.season &&
            analysis.seasonNumber != null) {
          final seasonNumber = analysis.seasonNumber!;
          final builder = builders.putIfAbsent(
            seasonNumber,
            _SeasonBuilder.new,
          );
          builder.directories.add(entry);
          builder.year ??= analysis.year;
          _collectSeasonEpisodes(
            directoryPath: _pathOf(entry),
            folderSeasonNumber: seasonNumber,
            inheritedReleaseTags: analysis.releaseTags,
            episodes: builder.episodes,
            aliases: aliases,
            visited: <String>{},
          );
        } else if (!entry.isDirectory && _isRecognizedVideo(entry)) {
          standaloneVideos.add(entry);
          standaloneReleaseTags[_pathOf(entry)] = analysis.releaseTags;
        } else if (entry.isDirectory) {
          if (nameAnalyzer.isTransparentDirectoryName(entry.name)) {
            transparentDirectories.add(entry);
          }
          _collectStandaloneVideos(
            directoryPath: _pathOf(entry),
            videos: standaloneVideos,
            inheritedReleaseTags: analysis.releaseTags,
            releaseTagsByEntry: standaloneReleaseTags,
            visited: <String>{},
          );
        } else {
          _ignore(entry);
        }
      }
      _promoteImplicitEpisodes(
        builders: builders,
        standaloneVideos: standaloneVideos,
        releaseTagsByEntry: standaloneReleaseTags,
        transparentDirectories: transparentDirectories,
        aliases: aliases,
        defaultSeasonNumber: rootAnalysis.seasonNumber,
      );
    }

    final seasonNumbers = builders.keys.toList(growable: false)..sort();
    final titleCandidates = _workTitleCandidates(
      root,
      rootAnalysis,
      seasonNumbers,
      aliases,
      includeRootTitleCandidates: includeRootTitleCandidates,
    );
    final displayTitle = titleCandidates.first;
    final seasons = <CloudSeasonIdentity>[];
    for (final seasonNumber in seasonNumbers) {
      final builder = builders[seasonNumber]!;
      builder.directories.sort(
        (first, second) => first.remotePath.compareTo(second.remotePath),
      );
      builder.episodes.sort((first, second) {
        final number = first.episodeNumber.compareTo(second.episodeNumber);
        return number != 0
            ? number
            : first.entry.remotePath.compareTo(second.entry.remotePath);
      });
      seasons.add(
        CloudSeasonIdentity(
          workKey: workKey,
          seasonNumber: seasonNumber,
          displayName: '$displayTitle 第 $seasonNumber 季',
          remoteDirectories:
              List<CloudFileEntry>.unmodifiable(builder.directories),
          episodes: List<CloudEpisodeIdentity>.unmodifiable(
            builder.episodes.map(
              (episode) => CloudEpisodeIdentity(
                entry: episode.entry,
                remoteName: episode.entry.name,
                displayName: _episodeDisplayName(
                  displayTitle,
                  seasonNumber,
                  episode.episodeNumber,
                  episode.entry.name,
                ),
                seasonNumber: seasonNumber,
                episodeNumber: episode.episodeNumber,
                releaseTags: episode.releaseTags,
              ),
            ),
          ),
          year: builder.year,
        ),
      );
    }
    if (seasons.isNotEmpty) {
      _works.add(
        CloudWorkIdentity(
          sourceId: sourceId,
          workKey: workKey,
          root: root,
          remoteName: root.name,
          displayTitle: displayTitle,
          titleCandidates: List<String>.unmodifiable(titleCandidates),
          seasons: List<CloudSeasonIdentity>.unmodifiable(seasons),
        ),
      );
    }
    _addStandaloneMovieWorks(
      root: root,
      videos: standaloneVideos,
      releaseTagsByEntry: standaloneReleaseTags,
    );
  }

  void _addStandaloneMovieWorks({
    required CloudFileEntry root,
    required List<CloudFileEntry> videos,
    required Map<String, MediaReleaseTags> releaseTagsByEntry,
  }) {
    final groups = <String, _MovieBuilder>{};
    for (final video in videos) {
      final analysis = nameAnalyzer.analyze(video.name, isDirectory: false);
      final candidates = analysis.titleCandidates.isEmpty
          ? <String>[p.basenameWithoutExtension(video.name).trim()]
          : List<String>.from(analysis.titleCandidates);
      final displayTitle = candidates.first;
      final identityKey = _movieIdentityKey(analysis, video, displayTitle);
      final builder = groups.putIfAbsent(
        identityKey,
        () => _MovieBuilder(
          identityKey: identityKey,
          displayTitle: displayTitle,
        ),
      );
      builder.videos.add(video);
      for (final candidate in candidates) {
        _addUnique(builder.titleCandidates, candidate);
      }
      builder.releaseTags[_pathOf(video)] =
          releaseTagsByEntry[_pathOf(video)] ?? analysis.releaseTags;
    }
    for (final builder in groups.values) {
      builder.videos.sort(
        (first, second) => first.remotePath.compareTo(second.remotePath),
      );
      _works.add(
        CloudWorkIdentity(
          sourceId: sourceId,
          workKey: movieWorkKeyFor(sourceId, root, builder.identityKey),
          root: root,
          remoteName: root.name,
          displayTitle: builder.displayTitle,
          titleCandidates: List<String>.unmodifiable(builder.titleCandidates),
          seasons: const <CloudSeasonIdentity>[],
          standaloneVideos: List<CloudFileEntry>.unmodifiable(builder.videos),
          standaloneReleaseTags: builder.releaseTags,
        ),
      );
    }
  }

  String _movieIdentityKey(
    MediaNameAnalysis analysis,
    CloudFileEntry entry,
    String displayTitle,
  ) {
    final normalizedTitle = displayTitle.trim().toLowerCase();
    if (normalizedTitle.isEmpty) return 'remote:${_pathOf(entry)}';
    return '$normalizedTitle|${analysis.year ?? 0}';
  }

  void _collectStandaloneVideos({
    required String directoryPath,
    required List<CloudFileEntry> videos,
    required MediaReleaseTags inheritedReleaseTags,
    required Map<String, MediaReleaseTags> releaseTagsByEntry,
    required Set<String> visited,
  }) {
    if (!visited.add(directoryPath)) return;
    final entries = directoryEntries[directoryPath] ?? const <CloudFileEntry>[];
    for (final entry in entries) {
      final analysis = nameAnalyzer.analyze(
        entry.name,
        isDirectory: entry.isDirectory,
      );
      if (_shouldIgnoreAdvertisement(entry, analysis)) {
        _ignoreTree(entry);
      } else if (entry.isDirectory) {
        _collectStandaloneVideos(
          directoryPath: _pathOf(entry),
          videos: videos,
          inheritedReleaseTags: _mergeReleaseTags(
            analysis.releaseTags,
            inheritedReleaseTags,
          ),
          releaseTagsByEntry: releaseTagsByEntry,
          visited: visited,
        );
      } else if (_isRecognizedVideo(entry)) {
        videos.add(entry);
        releaseTagsByEntry[_pathOf(entry)] = _mergeReleaseTags(
          analysis.releaseTags,
          inheritedReleaseTags,
        );
      } else {
        _ignore(entry);
      }
    }
  }

  void _promoteImplicitEpisodes({
    required Map<int, _SeasonBuilder> builders,
    required List<CloudFileEntry> standaloneVideos,
    required Map<String, MediaReleaseTags> releaseTagsByEntry,
    required List<CloudFileEntry> transparentDirectories,
    required List<String> aliases,
    int? defaultSeasonNumber,
  }) {
    if (builders.isNotEmpty || standaloneVideos.length < 2) return;
    final parsed = <({
      CloudFileEntry entry,
      int seasonNumber,
      int episodeNumber,
      MediaReleaseTags releaseTags,
    })>[];
    for (final video in standaloneVideos) {
      final analysis = nameAnalyzer.analyze(video.name, isDirectory: false);
      final parsedEpisode = episodeParser.parse(video.name);
      final fallback =
          analysis.episodeNumber == null && parsedEpisode?.episodeNumber == null
              ? _trailingEpisodeCandidate(video)
              : null;
      final episodeNumber = analysis.episodeNumber ??
          parsedEpisode?.episodeNumber ??
          fallback?.episodeNumber;
      if (episodeNumber == null || episodeNumber <= 0) continue;
      final parsedTitle = parsedEpisode?.seriesName.trim();
      if (parsedTitle != null && parsedTitle.isNotEmpty) {
        _addUnique(aliases, parsedTitle);
      }
      for (final title
          in fallback?.titleCandidates ?? analysis.titleCandidates) {
        _addUnique(aliases, title);
      }
      parsed.add((
        entry: video,
        seasonNumber: analysis.seasonNumber ??
            parsedEpisode?.seasonNumber ??
            defaultSeasonNumber ??
            fallback?.seasonNumber ??
            1,
        episodeNumber: episodeNumber,
        releaseTags: releaseTagsByEntry[_pathOf(video)] ??
            fallback?.releaseTags ??
            analysis.releaseTags,
      ));
    }
    if (parsed.length < 2) return;
    final episodePaths = parsed.map((item) => _pathOf(item.entry)).toSet();
    standaloneVideos.removeWhere(
      (video) => episodePaths.contains(_pathOf(video)),
    );
    final seasonNumbers = parsed.map((item) => item.seasonNumber).toSet();
    for (final item in parsed) {
      final builder = builders.putIfAbsent(
        item.seasonNumber,
        _SeasonBuilder.new,
      );
      builder.episodes.add(
        _ParsedEpisode(
          entry: item.entry,
          episodeNumber: item.episodeNumber,
          releaseTags: item.releaseTags,
        ),
      );
    }
    if (seasonNumbers.length == 1) {
      builders[seasonNumbers.single]!.directories.addAll(
            transparentDirectories,
          );
    }
  }

  void _collectSeasonEpisodes({
    required String directoryPath,
    required int folderSeasonNumber,
    required MediaReleaseTags inheritedReleaseTags,
    required List<_ParsedEpisode> episodes,
    required List<String> aliases,
    required Set<String> visited,
  }) {
    if (!visited.add(directoryPath)) return;
    final entries = directoryEntries[directoryPath] ?? const <CloudFileEntry>[];
    for (final entry in entries) {
      final analysis = nameAnalyzer.analyze(
        entry.name,
        isDirectory: entry.isDirectory,
      );
      if (_shouldIgnoreAdvertisement(entry, analysis)) {
        _ignoreTree(entry);
        continue;
      }
      if (entry.isDirectory) {
        _collectSeasonEpisodes(
          directoryPath: _pathOf(entry),
          folderSeasonNumber: folderSeasonNumber,
          inheritedReleaseTags: _mergeReleaseTags(
            analysis.releaseTags,
            inheritedReleaseTags,
          ),
          episodes: episodes,
          aliases: aliases,
          visited: visited,
        );
        continue;
      }
      if (!_isRecognizedVideo(entry)) {
        _ignore(entry);
        continue;
      }
      final parsed = episodeParser.parse(entry.name);
      final detectedSeason = analysis.seasonNumber ?? parsed?.seasonNumber;
      if (detectedSeason != null && detectedSeason != folderSeasonNumber) {
        _conflicts.add(
          CloudMediaTreeConflict(
            entry: entry,
            folderSeasonNumber: folderSeasonNumber,
            detectedSeasonNumber: detectedSeason,
          ),
        );
        continue;
      }
      final episodeNumber = analysis.episodeNumber ?? parsed?.episodeNumber;
      final leadingEpisodeNumber =
          episodeNumber == null ? _leadingEpisodeNumber(entry.name) : null;
      final resolvedEpisodeNumber = episodeNumber ?? leadingEpisodeNumber;
      if (resolvedEpisodeNumber == null || resolvedEpisodeNumber <= 0) {
        _ignore(entry);
        continue;
      }
      if (leadingEpisodeNumber == null) {
        for (final candidate in analysis.titleCandidates) {
          _addUnique(aliases, candidate);
        }
      }
      final parsedTitle = parsed?.seriesName.trim();
      if (parsedTitle != null && parsedTitle.isNotEmpty) {
        _addUnique(aliases, parsedTitle);
      }
      episodes.add(
        _ParsedEpisode(
          entry: entry,
          episodeNumber: resolvedEpisodeNumber,
          releaseTags: _mergeReleaseTags(
            analysis.releaseTags,
            inheritedReleaseTags,
          ),
        ),
      );
    }
  }

  int? _leadingEpisodeNumber(String fileName) {
    final baseName = p.basenameWithoutExtension(fileName).trim();
    final match = _leadingEpisodePattern.firstMatch(baseName);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  void _resolveStandaloneFile(CloudFileEntry entry) {
    final path = _pathOf(entry);
    if (!_resolvedWorkRoots.add(path)) return;
    final analysis = nameAnalyzer.analyze(entry.name, isDirectory: false);
    final candidates = analysis.titleCandidates.isEmpty
        ? <String>[p.basenameWithoutExtension(entry.name).trim()]
        : List<String>.from(analysis.titleCandidates);
    _works.add(
      CloudWorkIdentity(
        sourceId: sourceId,
        workKey: movieWorkKeyFor(
          sourceId,
          entry,
          _movieIdentityKey(analysis, entry, candidates.first),
        ),
        root: entry,
        remoteName: entry.name,
        displayTitle: candidates.first,
        titleCandidates: List<String>.unmodifiable(candidates),
        seasons: const <CloudSeasonIdentity>[],
        standaloneVideos: <CloudFileEntry>[entry],
        standaloneReleaseTags: <String, MediaReleaseTags>{
          _pathOf(entry): analysis.releaseTags,
        },
      ),
    );
  }

  List<String> _workTitleCandidates(
    CloudFileEntry root,
    MediaNameAnalysis rootAnalysis,
    List<int> seasonNumbers,
    List<String> aliases, {
    required bool includeRootTitleCandidates,
  }) {
    final result = <String>[];
    for (final alias in aliases) {
      _addUnique(result, alias);
    }
    final sourceCandidates = includeRootTitleCandidates
        ? (rootAnalysis.titleCandidates.isEmpty
            ? <String>[root.name.trim()]
            : rootAnalysis.titleCandidates)
        : const <String>[];
    final highestSeason = seasonNumbers.isEmpty ? null : seasonNumbers.last;
    for (final candidate in sourceCandidates) {
      final normalized = _withoutCollectionSeasonSuffix(
        candidate,
        seasonNumbers,
        highestSeason,
      );
      _addUnique(result, normalized);
      _addUnique(result, candidate);
    }
    if (result.isEmpty) _addUnique(result, root.name.trim());
    return result;
  }

  bool _shouldIgnoreAdvertisement(
    CloudFileEntry entry,
    MediaNameAnalysis analysis,
  ) {
    if (analysis.role != MediaNodeRole.advertisement) return false;
    if (!entry.isDirectory) return true;
    return !_containsRecognizedVideo(_pathOf(entry), <String>{});
  }

  String _withoutCollectionSeasonSuffix(
    String candidate,
    List<int> seasonNumbers,
    int? highestSeason,
  ) {
    if (seasonNumbers.length < 2 || highestSeason == null) return candidate;
    final match = RegExp(r'^(.*\D)(\d{1,2})$').firstMatch(candidate.trim());
    if (match == null || int.tryParse(match.group(2)!) != highestSeason) {
      return candidate;
    }
    final title = match.group(1)!.trimRight();
    return title.isEmpty ? candidate : title;
  }

  String _episodeDisplayName(
    String title,
    int seasonNumber,
    int episodeNumber,
    String remoteName,
  ) {
    final season = seasonNumber.toString().padLeft(2, '0');
    final episode = episodeNumber.toString().padLeft(2, '0');
    return '$title S${season}E$episode${p.extension(remoteName)}';
  }

  MediaReleaseTags _mergeReleaseTags(
    MediaReleaseTags primary,
    MediaReleaseTags fallback,
  ) {
    List<String> merged(List<String> first, List<String> second) {
      final result = <String>[];
      for (final value in <String>[...first, ...second]) {
        if (!result.contains(value)) result.add(value);
      }
      return result;
    }

    return MediaReleaseTags(
      resolution: primary.resolution ?? fallback.resolution,
      bitrate: primary.bitrate ?? fallback.bitrate,
      source: primary.source ?? fallback.source,
      codec: primary.codec ?? fallback.codec,
      dynamicRange: merged(primary.dynamicRange, fallback.dynamicRange),
      audio: merged(primary.audio, fallback.audio),
      subtitles: merged(primary.subtitles, fallback.subtitles),
      releaseGroup: primary.releaseGroup ?? fallback.releaseGroup,
    );
  }

  bool _isRecognizedVideo(CloudFileEntry entry) {
    return LocalVideoFileTypes.isRecognizedVideo(
      entry.remotePath,
      size: entry.size,
      minSizeBytes: minSizeBytes,
    );
  }

  void _ignoreTree(CloudFileEntry entry) {
    _ignore(entry);
    if (!entry.isDirectory) return;
    final entries =
        directoryEntries[_pathOf(entry)] ?? const <CloudFileEntry>[];
    for (final child in entries) {
      _ignoreTree(child);
    }
  }

  void _ignore(CloudFileEntry entry) {
    final key = entry.id.trim().isEmpty ? _pathOf(entry) : entry.id.trim();
    if (_ignoredKeys.add(key)) _ignored.add(entry);
  }

  String _pathOf(CloudFileEntry entry) =>
      CloudSeriesIdentityResolver.normalizeRemotePath(entry.remotePath);

  String? _nearestWorkName(String directoryPath) {
    var parent = p.posix.dirname(directoryPath);
    while (parent != '.' && parent != '/' && parent.isNotEmpty) {
      final candidate = p.posix.basename(parent).trim();
      final analysis = nameAnalyzer.analyze(candidate, isDirectory: true);
      if (candidate.isNotEmpty &&
          !nameAnalyzer.isTransparentDirectoryName(candidate) &&
          analysis.role != MediaNodeRole.season) {
        return candidate;
      }
      parent = p.posix.dirname(parent);
    }
    return null;
  }

  void _addUnique(List<String> values, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return;
    if (!values
        .any((current) => current.toLowerCase() == normalized.toLowerCase())) {
      values.add(normalized);
    }
  }

  String workKeyFor(String sourceId, CloudFileEntry root) {
    final stableRoot = root.id.trim().isEmpty
        ? CloudSeriesIdentityResolver.normalizeRemotePath(root.remotePath)
        : root.id.trim();
    return '$sourceId|work|$stableRoot';
  }

  String movieWorkKeyFor(
    String sourceId,
    CloudFileEntry root,
    String identityKey,
  ) {
    final stableBoundary = '${root.id.trim()}|${_pathOf(root)}';
    final digest =
        sha256.convert(utf8.encode('$stableBoundary|$identityKey')).toString();
    return '$sourceId|movie|$digest';
  }
}

class _SeasonBuilder {
  _SeasonBuilder();

  final List<CloudFileEntry> directories = <CloudFileEntry>[];
  final List<_ParsedEpisode> episodes = <_ParsedEpisode>[];
  int? year;
}

class _MovieBuilder {
  _MovieBuilder({
    required this.identityKey,
    required this.displayTitle,
  });

  final String identityKey;
  final String displayTitle;
  final List<String> titleCandidates = <String>[];
  final List<CloudFileEntry> videos = <CloudFileEntry>[];
  final Map<String, MediaReleaseTags> releaseTags =
      <String, MediaReleaseTags>{};
}

class _ParsedEpisode {
  const _ParsedEpisode({
    required this.entry,
    required this.episodeNumber,
    required this.releaseTags,
  });

  final CloudFileEntry entry;
  final int episodeNumber;
  final MediaReleaseTags releaseTags;
}

class _FlatEpisodeCandidate {
  const _FlatEpisodeCandidate({
    required this.entry,
    required this.seriesName,
    required this.titleCandidates,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.releaseTags,
    required this.strongEvidence,
  });

  final CloudFileEntry entry;
  final String seriesName;
  final List<String> titleCandidates;
  final int seasonNumber;
  final int episodeNumber;
  final MediaReleaseTags releaseTags;
  final bool strongEvidence;
}
