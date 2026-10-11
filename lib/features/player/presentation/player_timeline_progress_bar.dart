import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/features/player/application/local_timeline_thumbnail_cache.dart';
import 'package:kanyingyin/features/player/application/player_timeline_segments.dart';

class PlayerTimelineProgressBar extends StatefulWidget {
  const PlayerTimelineProgressBar({
    super.key,
    required this.progress,
    required this.buffered,
    required this.total,
    required this.onSeek,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.videoPath,
    this.enablePreview = true,
    this.thumbRadius = 8,
    this.thumbGlowRadius = 18,
    this.timeLabelLocation = TimeLabelLocation.none,
    this.timeLabelTextStyle,
    this.segments = const [],
  });

  final Duration progress;
  final Duration? buffered;
  final Duration total;
  final ValueChanged<Duration> onSeek;
  final ThumbDragStartCallback onDragStart;
  final ThumbDragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;
  final String? videoPath;
  final bool enablePreview;
  final double thumbRadius;
  final double thumbGlowRadius;
  final TimeLabelLocation timeLabelLocation;
  final TextStyle? timeLabelTextStyle;
  final List<PlayerTimelineSegment> segments;

  @override
  State<PlayerTimelineProgressBar> createState() =>
      _PlayerTimelineProgressBarState();
}

class _PlayerTimelineProgressBarState extends State<PlayerTimelineProgressBar> {
  late final LocalTimelineThumbnailCache _cache;
  String? _previewPath;
  Duration? _previewPosition;
  double _previewX = 0;
  int _previewRequest = 0;
  int? _lastBucket;

  bool get _supportsPreview {
    if (!widget.enablePreview) return false;
    final path = widget.videoPath?.trim();
    return path != null && path.isNotEmpty && File(path).existsSync();
  }

  @override
  void initState() {
    super.initState();
    _cache = LocalTimelineThumbnailCache();
  }

  @override
  void didUpdateWidget(covariant PlayerTimelineProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoPath != widget.videoPath ||
        oldWidget.total != widget.total ||
        oldWidget.enablePreview != widget.enablePreview) {
      _clearPreview(cancelPending: true);
    }
  }

  @override
  void dispose() {
    _cache.cancelPending();
    _previewRequest++;
    super.dispose();
  }

  void _clearPreview({required bool cancelPending}) {
    if (cancelPending) _cache.cancelPending();
    _previewRequest++;
    _lastBucket = null;
    if (mounted) {
      setState(() {
        _previewPath = null;
        _previewPosition = null;
      });
    } else {
      _previewPath = null;
      _previewPosition = null;
    }
  }

  Duration _positionForX(double x, double width) {
    if (widget.total <= Duration.zero || width <= 0) return Duration.zero;
    final ratio = (x / width).clamp(0.0, 1.0);
    return Duration(
      milliseconds: (widget.total.inMilliseconds * ratio).round(),
    );
  }

  void _requestPreview({
    required Duration position,
    required double x,
    required double width,
  }) {
    if (!_supportsPreview || widget.total <= Duration.zero) {
      _clearPreview(cancelPending: false);
      return;
    }
    final videoPath = widget.videoPath!.trim();
    final bucket = _cache.bucketFor(
      position: position,
      duration: widget.total,
    );
    if (_lastBucket == bucket) {
      if (mounted) {
        setState(() {
          _previewX = x;
        });
      }
      return;
    }
    _lastBucket = bucket;
    _cache.cancelPending();
    final request = ++_previewRequest;
    final previewPosition = _cache.positionForBucket(
      bucket: bucket,
      duration: widget.total,
    );
    if (mounted) {
      setState(() {
        _previewPath = null;
        _previewPosition = previewPosition;
        _previewX = x.clamp(0.0, width);
      });
    }
    unawaited(() async {
      final path = await _cache.thumbnailAt(
        videoPath: videoPath,
        position: position,
        duration: widget.total,
      );
      if (!mounted || request != _previewRequest) return;
      setState(() {
        _previewPath = path;
      });
    }());
  }

  void _handleHover(PointerHoverEvent event, double width) {
    final bounds = _trackBounds(context, width);
    _requestPreview(
      position:
          _positionForX(event.localPosition.dx - bounds.left, bounds.width),
      x: event.localPosition.dx,
      width: width,
    );
  }

  ({double left, double width}) _trackBounds(
      BuildContext context, double width) {
    if (widget.timeLabelLocation != TimeLabelLocation.sides) {
      return (left: 0, width: width);
    }
    double labelWidth(Duration time) {
      final minutes = time.inMinutes.remainder(60).toString();
      final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');
      final text = time.inHours > 0
          ? '${time.inHours}:${minutes.padLeft(2, '0')}:$seconds'
          : '$minutes:$seconds';
      final painter = TextPainter(
          text: TextSpan(
              text: text,
              style: widget.timeLabelTextStyle ??
                  Theme.of(context).textTheme.bodyLarge),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context))
        ..layout();
      final result = painter.width;
      painter.dispose();
      return result;
    }

    final left = labelWidth(widget.progress) + widget.thumbRadius + 5;
    final right = labelWidth(widget.total) + widget.thumbRadius + 5;
    return (left: left, width: math.max(0, width - left - right));
  }

  List<Widget> _buildMarkers(BuildContext context, double width) {
    if (widget.total <= Duration.zero) return const [];
    final bounds = _trackBounds(context, width);
    if (bounds.width <= 0) return const [];
    final children = <Widget>[];
    for (final segment in widget.segments) {
      final start = bounds.left +
          bounds.width *
              (segment.start.inMilliseconds / widget.total.inMilliseconds)
                  .clamp(0, 1);
      final end = bounds.left +
          bounds.width *
              (segment.end.inMilliseconds / widget.total.inMilliseconds)
                  .clamp(0, 1);
      final color = segment.kind == PlayerSegmentKind.intro
          ? Theme.of(context).colorScheme.secondary
          : Theme.of(context).colorScheme.tertiary;
      children.add(Positioned(
          left: start,
          top: -4,
          width: math.max(1, end - start),
          height: 3,
          child: IgnorePointer(child: ColoredBox(color: color))));
      for (final x in [start, end]) {
        children.add(Positioned(
            left: x - 0.5,
            top: -4,
            width: 1,
            height: 8,
            child: IgnorePointer(child: ColoredBox(color: color))));
      }
      children.add(Positioned(
          left: ((start + end) / 2 - 14).clamp(0, math.max(0, width - 28)),
          top: -18,
          width: 28,
          child: IgnorePointer(
              child: Text(segment.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: color)))));
    }
    return children;
  }

  Widget _buildPreview(double width) {
    final path = _previewPath;
    final position = _previewPosition;
    if (path == null || position == null) return const SizedBox.shrink();
    const previewWidth = 160.0;
    const previewHeight = 90.0;
    final left = (_previewX - previewWidth / 2)
        .clamp(0.0, math.max(0.0, width - previewWidth))
        .toDouble();
    return Positioned(
      left: left,
      bottom: 24,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.file(
                  File(path),
                  width: previewWidth,
                  height: previewHeight,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: previewWidth,
                    height: previewHeight,
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDuration(position),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MouseRegion(
          onHover: (event) => _handleHover(event, width),
          onExit: (_) => _clearPreview(cancelPending: true),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ProgressBar(
                thumbRadius: widget.thumbRadius,
                thumbGlowRadius: widget.thumbGlowRadius,
                timeLabelLocation: widget.timeLabelLocation,
                timeLabelTextStyle: widget.timeLabelTextStyle,
                progress: widget.progress,
                buffered: widget.buffered,
                total: widget.total,
                onSeek: widget.onSeek,
                onDragStart: (details) {
                  _requestPreview(
                    position: details.timeStamp,
                    x: details.localPosition.dx,
                    width: width,
                  );
                  widget.onDragStart(details);
                },
                onDragUpdate: (details) {
                  _requestPreview(
                    position: details.timeStamp,
                    x: details.localPosition.dx,
                    width: width,
                  );
                  widget.onDragUpdate(details);
                },
                onDragEnd: () {
                  _clearPreview(cancelPending: true);
                  widget.onDragEnd();
                },
              ),
              ..._buildMarkers(context, width),
              _buildPreview(width),
            ],
          ),
        );
      },
    );
  }
}

String _formatDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
