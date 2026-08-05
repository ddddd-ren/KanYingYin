import 'package:path/path.dart' as p;

/// 将 TMDB 的逐集名称转换为媒体库展示标题，不改变文件或播放身份。
class TmdbEpisodeTitleResolver {
  const TmdbEpisodeTitleResolver();

  String resolve({
    required String? seriesTitle,
    required int? seasonNumber,
    required int? episodeNumber,
    required String? episodeName,
    required String? originalFileName,
  }) {
    final title = seriesTitle?.trim() ?? '';
    final original = originalFileName?.trim() ?? '';
    final episode = episodeNumber;
    if (title.isEmpty) return original;
    if (episode == null || episode <= 0) {
      return original.isEmpty ? title : original;
    }
    final episodeLabel = 'E${episode.toString().padLeft(2, '0')}';
    final season = seasonNumber;
    final prefix = season != null && season > 0
        ? '$title S${season.toString().padLeft(2, '0')}$episodeLabel'
        : '$title $episodeLabel';
    final name = episodeName?.trim() ?? '';
    return name.isEmpty ? prefix : '$prefix $name';
  }

  String resolveWithExtension({
    required String? seriesTitle,
    required int? seasonNumber,
    required int? episodeNumber,
    required String? episodeName,
    required String originalFileName,
  }) {
    final resolved = resolve(
      seriesTitle: seriesTitle,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeName: episodeName,
      originalFileName: originalFileName,
    );
    if (resolved == originalFileName || p.extension(originalFileName).isEmpty) {
      return resolved;
    }
    if (p.extension(resolved).isNotEmpty) return resolved;
    return '$resolved${p.extension(originalFileName)}';
  }
}
