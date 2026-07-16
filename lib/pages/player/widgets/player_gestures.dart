import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/utils/utils.dart';

class PlayerGestures extends StatelessWidget {
  const PlayerGestures({
    super.key,
    required this.playerController,
    required this.animationController,
    required this.brightnessVolumeGesture,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onSeek,
    required this.onSetBrightness,
    required this.startHideTimer,
  });

  final PlayerController playerController;
  final AnimationController animationController;
  final bool brightnessVolumeGesture;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final void Function(Duration) onSeek;
  final Future<void> Function(double) onSetBrightness;
  final VoidCallback startHideTimer;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      left: 16,
      top: 25,
      right: 15,
      bottom: 15,
      child: (Utils.isDesktop() || playerController.lockPanel)
          ? Container()
          : GestureDetector(
              onHorizontalDragStart: (_) {
                if (!playerController.showVideoController) {
                  animationController.forward();
                }
                playerController.canHidePlayerPanel = false;
              },
              onHorizontalDragUpdate: (DragUpdateDetails details) {
                playerController.showSeekTime = true;
                onDragStart();
                final double scale =
                    180000 / MediaQuery.sizeOf(context).width;
                int ms = (playerController.currentPosition.inMilliseconds +
                        (details.delta.dx * scale).round())
                    .clamp(0, playerController.duration.inMilliseconds);
                playerController.currentPosition = Duration(milliseconds: ms);
              },
              onHorizontalDragEnd: (_) {
                onSeek(playerController.currentPosition);
                playerController.canHidePlayerPanel = true;
                if (!playerController.showVideoController) {
                  animationController.reverse();
                } else {
                  startHideTimer();
                }
                playerController.showSeekTime = false;
                onDragEnd();
              },
              onVerticalDragUpdate: (DragUpdateDetails details) async {
                if (!brightnessVolumeGesture) {
                  return;
                }
                final double totalWidth =
                    MediaQuery.sizeOf(context).width;
                final double totalHeight =
                    MediaQuery.sizeOf(context).height;
                final double tapPosition = details.localPosition.dx;
                final double sectionWidth = totalWidth / 2;
                final double delta = details.delta.dy;

                if (tapPosition < sectionWidth) {
                  playerController.brightnessSeeking = true;
                  playerController.showBrightness = true;
                  final double level = (totalHeight) * 2;
                  final double brightness =
                      playerController.brightness - delta / level;
                  final double result = brightness.clamp(0.0, 1.0);
                  onSetBrightness(result);
                  playerController.brightness = result;
                } else {
                  playerController.volumeSeeking = true;
                  playerController.showVolume = true;
                  final double level = (totalHeight) * 0.03;
                  final double volume =
                      playerController.volume - delta / level;
                  playerController.setVolume(volume);
                }
              },
              onVerticalDragEnd: (_) {
                if (!brightnessVolumeGesture) {
                  return;
                }
                if (playerController.volumeSeeking) {
                  playerController.volumeSeeking = false;
                  Future.delayed(const Duration(seconds: 1), () {
                    FlutterVolumeController.updateShowSystemUI(true);
                  });
                }
                if (playerController.brightnessSeeking) {
                  playerController.brightnessSeeking = false;
                }
                playerController.showVolume = false;
                playerController.showBrightness = false;
              },
            ),
    );
  }
}
