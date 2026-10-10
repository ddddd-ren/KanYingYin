import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';
import 'package:kanyingyin/utils/logger.dart';

/// 记录 TMDB 换图在选择、保存、同步和显示边界的同一组字段。
class TmdbImageSelectionLogger {
  const TmdbImageSelectionLogger._();

  static void write({
    required String scope,
    required String phase,
    required String target,
    required TmdbImageKind kind,
    required String identity,
    int? tmdbId,
    int? seasonNumber,
    int? episodeNumber,
    int? candidateCount,
    String? previousPath,
    String? selectedPath,
    String? savedPath,
    String? repositoryReadBack,
    String? displayPath,
    bool? indexSynced,
    int? elapsedMs,
    String result = 'info',
    Object? error,
    StackTrace? stackTrace,
  }) {
    final fields = <String>[
      'scope=${_text(scope)}',
      'phase=${_text(phase)}',
      'target=${_text(target)}',
      'kind=${kind.name}',
      'identity=${_text(identity)}',
      'result=${_text(result)}',
      if (tmdbId != null) 'tmdbId=$tmdbId',
      if (seasonNumber != null) 'season=$seasonNumber',
      if (episodeNumber != null) 'episode=$episodeNumber',
      if (candidateCount != null) 'candidateCount=$candidateCount',
      if (previousPath != null) 'previous=${_path(previousPath)}',
      if (selectedPath != null) 'selected=${_path(selectedPath)}',
      if (savedPath != null) 'saved=${_path(savedPath)}',
      if (repositoryReadBack != null) 'repository=${_path(repositoryReadBack)}',
      if (displayPath != null) 'display=${_path(displayPath)}',
      if (indexSynced != null) 'indexSynced=$indexSynced',
      if (elapsedMs != null) 'elapsedMs=$elapsedMs',
    ];
    final message = 'TMDB 图片选择: ${fields.join(' ')}';
    if (error != null) {
      AppLogger().e(message, error: error, stackTrace: stackTrace);
    } else {
      AppLogger().i(message);
    }
  }

  static String _path(String value) {
    final normalized = normalizeTmdbImagePath(value) ?? '-';
    final uri = Uri.tryParse(normalized);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return '${uri.scheme}://${uri.host}${uri.path}';
    }
    return _text(normalized);
  }

  static String _text(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (normalized.length <= 120) return normalized;
    return '${normalized.substring(0, 117)}...';
  }
}
