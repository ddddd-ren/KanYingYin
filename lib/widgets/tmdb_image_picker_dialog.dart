import 'package:flutter/material.dart';
import 'package:kanyingyin/modules/local/tmdb_image_metadata.dart';
import 'package:kanyingyin/widgets/tmdb_network_image.dart';

class TmdbImagePickerDialog extends StatefulWidget {
  const TmdbImagePickerDialog({
    super.key,
    required this.title,
    required this.images,
    required this.kind,
    this.currentPath,
  });

  final String title;
  final Future<TmdbImageSet> Function() images;
  final TmdbImageKind kind;
  final String? currentPath;

  static Future<TmdbImageCandidate?> show({
    required BuildContext context,
    required String title,
    required Future<TmdbImageSet> Function() images,
    required TmdbImageKind kind,
    String? currentPath,
  }) {
    return showDialog<TmdbImageCandidate>(
      context: context,
      builder: (_) => TmdbImagePickerDialog(
        title: title,
        images: images,
        kind: kind,
        currentPath: currentPath,
      ),
    );
  }

  @override
  State<TmdbImagePickerDialog> createState() => _TmdbImagePickerDialogState();
}

class _TmdbImagePickerDialogState extends State<TmdbImagePickerDialog> {
  late Future<TmdbImageSet> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.images();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 720,
        height: 520,
        child: FutureBuilder<TmdbImageSet>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _error(context, snapshot.error.toString());
            }
            final values = _values(snapshot.data ?? const TmdbImageSet());
            if (values.isEmpty) {
              return const Center(child: Text('TMDB 没有返回可用图片'));
            }
            return GridView.builder(
              padding: const EdgeInsets.only(top: 4),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _crossAxisCount(context),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio:
                    widget.kind == TmdbImageKind.poster ? 2 / 3 : 16 / 9,
              ),
              itemCount: values.length,
              itemBuilder: (context, index) => _tile(context, values[index]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _error(BuildContext context, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('加载图片失败'),
          const SizedBox(height: 8),
          Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(() => _future = widget.images()),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, TmdbImageCandidate image) {
    final selected = normalizeTmdbImagePath(image.filePath) ==
        normalizeTmdbImagePath(widget.currentPath);
    final url = image.url(
        size: widget.kind == TmdbImageKind.backdrop ? 'w780' : 'w342');
    return InkWell(
      onTap: () => Navigator.of(context).pop(image),
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TmdbNetworkImage(url: url, fit: BoxFit.cover),
          ),
          if (selected)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.check, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<TmdbImageCandidate> _values(TmdbImageSet images) {
    switch (widget.kind) {
      case TmdbImageKind.poster:
        return images.posters;
      case TmdbImageKind.backdrop:
        return images.backdrops;
      case TmdbImageKind.still:
        return images.stills;
    }
  }

  int _crossAxisCount(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1000) return 5;
    if (width >= 720) return 4;
    return 3;
  }
}
