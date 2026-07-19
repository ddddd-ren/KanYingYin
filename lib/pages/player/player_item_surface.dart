import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:media_kit_video/media_kit_video.dart';

bool shouldRenderFlutterSubtitleOverlay({
  required bool hasExternalSubtitle,
  required bool nativeSubtitleRendering,
}) =>
    hasExternalSubtitle && !nativeSubtitleRendering;

class PlayerItemSurface extends StatefulWidget {
  const PlayerItemSurface({super.key});

  @override
  State<PlayerItemSurface> createState() => _PlayerItemSurfaceState();
}

class _PlayerItemSurfaceState extends State<PlayerItemSurface> {
  final PlayerController playerController = Modular.get<PlayerController>();

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (context) {
      if (playerController.loading ||
          playerController.videoController == null) {
        return Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      final videoController = playerController.videoController!;
      final showSubtitle = shouldRenderFlutterSubtitleOverlay(
        hasExternalSubtitle: playerController.currentSubtitlePath.isNotEmpty,
        nativeSubtitleRendering:
            videoController.player.platform?.configuration.libass ?? false,
      );
      final subtitleStyle = playerController.subtitleStyleSettings;
      final outlineWidth = subtitleStyle.borderSize;
      final shadows = <Shadow>[
        if (outlineWidth > 0)
          for (final offset in [
            Offset(-outlineWidth, 0),
            Offset(outlineWidth, 0),
            Offset(0, -outlineWidth),
            Offset(0, outlineWidth),
            Offset(-outlineWidth, -outlineWidth),
            Offset(outlineWidth, -outlineWidth),
            Offset(-outlineWidth, outlineWidth),
            Offset(outlineWidth, outlineWidth),
          ])
            Shadow(
              offset: offset,
              blurRadius: outlineWidth / 2,
              color: subtitleStyle.borderColor,
            ),
        if (subtitleStyle.shadowEnabled && subtitleStyle.shadowOffset > 0)
          Shadow(
            offset: Offset(
              subtitleStyle.shadowOffset,
              subtitleStyle.shadowOffset,
            ),
            blurRadius: subtitleStyle.shadowOffset + 1,
            color: subtitleStyle.borderColor.withValues(alpha: 0.85),
          ),
      ];
      final subtitlePaddingBottom =
          24.0 + (100.0 - subtitleStyle.position) * 4.0;
      final subtitleTextStyle = TextStyle(
        color: subtitleStyle.color,
        fontSize: subtitleStyle.fontSize,
        background: Paint()..color = Colors.transparent,
        decoration: TextDecoration.none,
        fontWeight: FontWeight.bold,
        shadows: shadows,
      );

      return Stack(
        children: [
          Video(
            controller: videoController,
            controls: null,
            pauseUponEnteringBackgroundMode: false,
            fit: playerController.aspectRatioType == 1
                ? BoxFit.contain
                : playerController.aspectRatioType == 2
                    ? BoxFit.cover
                    : BoxFit.fill,
            subtitleViewConfiguration: const SubtitleViewConfiguration(
              visible: false,
            ),
          ),
          if (showSubtitle)
            Positioned.fill(
              child: _PrimarySubtitleView(
                controller: videoController,
                textStyle: subtitleTextStyle,
                padding: EdgeInsets.fromLTRB(
                  24.0,
                  0,
                  24.0,
                  subtitlePaddingBottom,
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _PrimarySubtitleView extends StatefulWidget {
  const _PrimarySubtitleView({
    required this.controller,
    required this.textStyle,
    required this.padding,
  });

  final VideoController controller;
  final TextStyle textStyle;
  final EdgeInsets padding;

  @override
  State<_PrimarySubtitleView> createState() => _PrimarySubtitleViewState();
}

class _PrimarySubtitleViewState extends State<_PrimarySubtitleView> {
  static const _referenceWidth = 1920.0;
  static const _referenceHeight = 1080.0;

  List<String> _subtitle = const ['', ''];
  StreamSubscription<List<String>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe(widget.controller);
  }

  @override
  void didUpdateWidget(covariant _PrimarySubtitleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _subscription?.cancel();
      _subscribe(widget.controller);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribe(VideoController controller) {
    _subtitle = controller.player.state.subtitle;
    _subscription = controller.player.stream.subtitle.listen((value) {
      if (!mounted) return;
      setState(() {
        _subtitle = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final primarySubtitle = _subtitle.isEmpty ? '' : _subtitle.first.trim();
    if (primarySubtitle.isEmpty) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final area = constraints.maxWidth * constraints.maxHeight;
          final referenceArea = _referenceWidth * _referenceHeight;
          final textScaleFactor = sqrt((area / referenceArea).clamp(0.0, 1.0));

          return Material(
            color: Colors.transparent,
            child: Padding(
              padding: widget.padding,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Text(
                  primarySubtitle,
                  style: widget.textStyle,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.linear(textScaleFactor),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
