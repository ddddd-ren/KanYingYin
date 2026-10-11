import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/player/application/embedded_track_language_preferences.dart';
import 'package:kanyingyin/features/player/application/player_runtime_preferences.dart';
import 'package:kanyingyin/features/player/application/subtitle_preferences.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/pages/player/player_controller.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/shaders/shaders_controller.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  late Directory root;
  late Box<Object?> box;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('kanyingyin-track-async-');
    Hive.init(root.path);
    box = await Hive.openBox<Object?>('settings');
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });
  test('关闭字幕失败时保留原选择和外置字幕路径', () async {
    final controller = PlayerController(
        runtimePreferences: PlayerRuntimePreferences(TypedSettings(box)),
        subtitlePreferences: SubtitlePreferences(storage: box),
        trackLanguagePreferences:
            EmbeddedTrackLanguagePreferences(storage: box),
        shadersController: ShadersController(),
        capabilities: AppPlatformCapabilities.windows);
    controller.mediaPlayer = _Player(failDisable: true);
    controller.selectedEmbeddedSubtitleTrackId = 'previous';
    controller.currentSubtitlePath = 'external.srt';
    await controller.clearSubtitle();
    expect(controller.selectedEmbeddedSubtitleTrackId, 'previous');
    expect(controller.currentSubtitlePath, 'external.srt');
  });
  for (final fails in [true, false]) {
    test('旧字幕关闭请求${fails ? '失败' : '成功'}不得清除后来的手动选择', () async {
      final controller = PlayerController(
          runtimePreferences: PlayerRuntimePreferences(TypedSettings(box)),
          subtitlePreferences: SubtitlePreferences(storage: box),
          trackLanguagePreferences:
              EmbeddedTrackLanguagePreferences(storage: box),
          shadersController: ShadersController(),
          capabilities: AppPlatformCapabilities.windows);
      final player = _Player(blockFirstDisable: true);
      controller.mediaPlayer = player;
      final pending = controller.selectEmbeddedSubtitleTrack('1', manual: false);
      await player.disableStarted.future;
      expect(await controller.selectEmbeddedSubtitleTrack('2'), isTrue);
      if (fails) {
        player.disableGate.completeError(StateError('旧关闭失败'));
      } else {
        player.disableGate.complete();
      }
      expect(await pending, isFalse);
      expect(controller.selectedEmbeddedSubtitleTrackId, '2');
    });
  }
  for (final subtitle in [false, true]) {
    for (final scenario in ['自动失败', '手动失败', '手动成功']) {
      test('${subtitle ? '字幕' : '音轨'}旧请求$scenario不得覆盖后来的手动选择', () async {
        final controller = PlayerController(
            runtimePreferences: PlayerRuntimePreferences(TypedSettings(box)),
            subtitlePreferences: SubtitlePreferences(storage: box),
            trackLanguagePreferences:
                EmbeddedTrackLanguagePreferences(storage: box),
            shadersController: ShadersController(),
            capabilities: AppPlatformCapabilities.windows);
        final player = _Player();
        controller.mediaPlayer = player;
        final pending = subtitle
            ? controller.selectEmbeddedSubtitleTrack('1',
                manual: scenario != '自动失败')
            : controller.selectAudioTrack('1', manual: scenario != '自动失败');
        final handled = pending.catchError((Object _) => false);
        await player.started.future;
        expect(
            await (subtitle
                ? controller.selectEmbeddedSubtitleTrack('2')
                : controller.selectAudioTrack('2')),
            isTrue);
        if (scenario.endsWith('失败')) {
          player.gate.completeError(StateError('旧请求失败'));
        } else {
          player.gate.complete();
        }
        await handled;
        expect(
            subtitle
                ? controller.selectedEmbeddedSubtitleTrackId
                : controller.selectedAudioTrackId,
            '2');
      });
    }
    for (final fails in [true, false]) {
      test('${subtitle ? '字幕' : '音轨'}旧请求${fails ? '失败' : '成功'}不得覆盖新媒体选轨状态',
          () async {
        final controller = PlayerController(
            runtimePreferences: PlayerRuntimePreferences(TypedSettings(box)),
            subtitlePreferences: SubtitlePreferences(storage: box),
            trackLanguagePreferences:
                EmbeddedTrackLanguagePreferences(storage: box),
            shadersController: ShadersController(),
            capabilities: AppPlatformCapabilities.windows);
        final old = _Player();
        controller.mediaPlayer = old;
        controller.selectedAudioTrackId = 'previous';
        controller.selectedEmbeddedSubtitleTrackId = 'previous';
        final pending = subtitle
            ? controller.selectEmbeddedSubtitleTrack('1')
            : controller.selectAudioTrack('1');
        final handled = pending.catchError((Object _) => false);
        await old.started.future;
        controller.mediaPlayer = _Player();
        controller.selectedAudioTrackId = 'new-media';
        controller.selectedEmbeddedSubtitleTrackId = 'new-media';
        if (fails) {
          old.gate.completeError(StateError('旧播放器已释放'));
        } else {
          old.gate.complete();
        }
        await handled;
        expect(
            subtitle
                ? controller.selectedEmbeddedSubtitleTrackId
                : controller.selectedAudioTrackId,
            'new-media');
      });
    }
  }
  test('外置字幕旧请求成功不得写入新媒体的字幕路径', () async {
    final controller = PlayerController(
        runtimePreferences: PlayerRuntimePreferences(TypedSettings(box)),
        subtitlePreferences: SubtitlePreferences(storage: box),
        trackLanguagePreferences:
            EmbeddedTrackLanguagePreferences(storage: box),
        shadersController: ShadersController(),
        capabilities: AppPlatformCapabilities.windows);
    final old = _Player();
    controller.mediaPlayer = old;
    final pending = controller.loadExternalSubtitle('external.srt');
    await old.started.future;
    controller.mediaPlayer = _Player();
    controller.currentSubtitlePath = 'new-media.srt';
    old.gate.complete();
    expect(await pending, isFalse);
    expect(controller.currentSubtitlePath, 'new-media.srt');
  });
}

class _Player extends Fake implements Player {
  _Player({this.failDisable = false, this.blockFirstDisable = false});
  final bool failDisable;
  final bool blockFirstDisable;
  final disableStarted = Completer<void>();
  final disableGate = Completer<void>();
  final started = Completer<void>();
  final gate = Completer<void>();
  @override
  PlatformPlayer? get platform => null;
  @override
  PlayerState get state => const PlayerState(
      tracks: Tracks(
          audio: [AudioTrack('1', null, 'ja'), AudioTrack('2', null, 'en')],
          subtitle: [SubtitleTrack('1', null, 'zh'), SubtitleTrack('2', null, 'en')]));
  @override
  Future<void> setAudioTrack(AudioTrack track) {
    if (track.id == '2') return Future.value();
    started.complete();
    return gate.future;
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) {
    if (track.id == 'no') {
      if (blockFirstDisable && !disableStarted.isCompleted) {
        disableStarted.complete();
        return disableGate.future;
      }
      return failDisable ? Future.error(StateError('关闭失败')) : Future.value();
    }
    if (track.id == '2') return Future.value();
    started.complete();
    return gate.future;
  }
}
