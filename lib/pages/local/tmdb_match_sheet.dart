import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';

class TmdbMatchSheet extends StatelessWidget {
  const TmdbMatchSheet({
    super.key,
    required this.seriesName,
    required this.candidates,
  });

  final String seriesName;
  final List<TmdbMetadata> candidates;

  static String? imageUrl(String? path, {String size = 'w342'}) {
    if (path == null || path.trim().isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return 'https://image.tmdb.org/t/p/$size$path';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择“$seriesName”的匹配结果',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Flexible(
              child: candidates.isEmpty
                  ? const Center(child: Text('TMDB 没有返回可用候选'))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = candidates[index];
                        final poster = imageUrl(item.posterUrl);
                        final year = item.releaseDate != null &&
                                item.releaseDate!.length >= 4
                            ? item.releaseDate!.substring(0, 4)
                            : '年份未知';
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 6),
                          leading: SizedBox(
                            width: 48,
                            height: 68,
                            child: poster == null
                                ? const Icon(Icons.movie_outlined)
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(poster,
                                        fit: BoxFit.cover),
                                  ),
                          ),
                          title: Text(item.title),
                          subtitle: Text([
                            if (item.originalTitle != null) item.originalTitle!,
                            year,
                            item.mediaType == TmdbMediaType.movie ? '电影' : '剧集',
                          ].join(' · ')),
                          trailing: const Icon(Icons.check_circle_outline),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
