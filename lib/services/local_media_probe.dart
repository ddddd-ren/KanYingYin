import 'dart:async';
import 'dart:io';

import 'package:kanyingyin/utils/logger.dart';
import 'package:media_kit/media_kit.dart';

class LocalMediaInfo {
  final Duration? duration;
  final int? width;
  final int? height;

  const LocalMediaInfo({
    this.duration,
    this.width,
    this.height,
  });

  bool get isEmpty {
    return (duration == null || duration! <= Duration.zero) &&
        ((width ?? 0) <= 0 || (height ?? 0) <= 0);
  }
}

abstract class ILocalMediaProbe {
  Future<LocalMediaInfo> probe(String filePath);
  Future<String?> captureThumbnail(String filePath, String outputPath);
}

class MediaKitLocalMediaProbe implements ILocalMediaProbe {
  MediaKitLocalMediaProbe({
    this.timeout = const Duration(seconds: 4),
  });

  final Duration timeout;

  @override
  Future<LocalMediaInfo> probe(String filePath) async {
    MediaKit.ensureInitialized();
    final player = Player();
    final subscriptions = <StreamSubscription<dynamic>>[];
    final completer = Completer<LocalMediaInfo>();
    Duration? duration;
    int? width;
    int? height;

    void completeIfReady() {
      final hasDuration = duration != null && duration! > Duration.zero;
      final hasSize = (width ?? 0) > 0 && (height ?? 0) > 0;
      if (!completer.isCompleted && (hasDuration || hasSize)) {
        completer.complete(LocalMediaInfo(
          duration: duration,
          width: width,
          height: height,
        ));
      }
    }

    try {
      subscriptions.add(player.stream.duration.listen((event) {
        if (event > Duration.zero) {
          duration = event;
          completeIfReady();
        }
      }));
      subscriptions.add(player.stream.videoParams.listen((event) {
        if ((event.dw ?? 0) > 0 && (event.dh ?? 0) > 0) {
          width = event.dw;
          height = event.dh;
          completeIfReady();
        }
      }));
      await player.setVolume(0);
      await player.open(Media(File(filePath).uri.toString()), play: false);

      final result = await completer.future.timeout(
        timeout,
        onTimeout: () => LocalMediaInfo(
          duration: player.state.duration > Duration.zero
              ? player.state.duration
              : duration,
          width: (player.state.videoParams.dw ?? 0) > 0
              ? player.state.videoParams.dw
              : width,
          height: (player.state.videoParams.dh ?? 0) > 0
              ? player.state.videoParams.dh
              : height,
        ),
      );
      return result.isEmpty ? const LocalMediaInfo() : result;
    } catch (e) {
      AppLogger().w(
        'MediaKitLocalMediaProbe: failed to probe $filePath',
        error: e,
      );
      return const LocalMediaInfo();
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await player.dispose();
    }
  }

  @override
  Future<String?> captureThumbnail(String filePath, String outputPath) async {
    MediaKit.ensureInitialized();
    final player = Player();
    final subscriptions = <StreamSubscription<dynamic>>[];
    final durationCompleter = Completer<Duration>();

    try {
      subscriptions.add(player.stream.duration.listen((event) {
        if (event > Duration.zero && !durationCompleter.isCompleted) {
          durationCompleter.complete(event);
        }
      }));
      await player.setVolume(0);
      await player.open(Media(File(filePath).uri.toString()), play: false);

      final duration = await durationCompleter.future.timeout(
        timeout,
        onTimeout: () => player.state.duration,
      );
      final position = _thumbnailPosition(duration);
      if (position > Duration.zero) {
        await player.seek(position);
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final image = await player.screenshot(format: 'image/jpeg').timeout(
            timeout,
            onTimeout: () => null,
          );
      if (image == null || image.isEmpty) return null;

      final outputFile = File(outputPath);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(image, flush: true);
      return outputFile.path;
    } catch (e) {
      AppLogger().w(
        'MediaKitLocalMediaProbe: failed to capture thumbnail $filePath',
        error: e,
      );
      return null;
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await player.dispose();
    }
  }

  Duration _thumbnailPosition(Duration duration) {
    if (duration <= Duration.zero) {
      return const Duration(seconds: 1);
    }
    if (duration > const Duration(minutes: 2)) {
      return const Duration(seconds: 30);
    }
    if (duration > const Duration(seconds: 20)) {
      return Duration(milliseconds: duration.inMilliseconds ~/ 5);
    }
    return const Duration(seconds: 1);
  }
}
