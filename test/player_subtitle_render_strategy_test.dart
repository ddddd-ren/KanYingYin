import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/player/player_item_surface.dart';

void main() {
  test('启用原生字幕渲染时不再叠加 Flutter 外部字幕层', () {
    expect(
      shouldRenderFlutterSubtitleOverlay(
        hasExternalSubtitle: true,
        nativeSubtitleRendering: true,
      ),
      isFalse,
    );
  });

  test('未启用原生字幕渲染时保留 Flutter 外部字幕层', () {
    expect(
      shouldRenderFlutterSubtitleOverlay(
        hasExternalSubtitle: true,
        nativeSubtitleRendering: false,
      ),
      isTrue,
    );
    expect(
      shouldRenderFlutterSubtitleOverlay(
        hasExternalSubtitle: false,
        nativeSubtitleRendering: false,
      ),
      isFalse,
    );
  });
}
