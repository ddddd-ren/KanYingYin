import 'package:kanyingyin/modules/media/media_name_analysis.dart';

class CloudFileEntry {
  const CloudFileEntry({
    required this.id,
    required this.remotePath,
    required this.name,
    required this.size,
    required this.modifiedAt,
    required this.isDirectory,
    this.seasonNumber,
    this.episodeNumber,
    this.variantLabel,
    this.releaseTags = const MediaReleaseTags(),
  });

  final String id;
  final String remotePath;
  final String name;
  final int size;
  final DateTime? modifiedAt;
  final bool isDirectory;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? variantLabel;
  final MediaReleaseTags releaseTags;
}
