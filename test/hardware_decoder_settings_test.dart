import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/constants.dart';

void main() {
  test('hardware decoder list matches selectable user modes', () {
    expect(hardwareDecodersList.keys, [
      'auto',
      'no',
      'auto-safe',
      'auto-copy',
      'd3d11va-copy',
      'd3d11va',
      'dxva2-copy',
      'dxva2',
    ]);
    expect(hardwareDecodersList.values, [
      '自动',
      'CPU兼容',
      '自动安全',
      '自动拷贝',
      'D3D11拷贝',
      'D3D11直通',
      'DXVA2拷贝',
      'DXVA2直通',
    ]);
  });

  test('normalizeHardwareDecoder falls back to auto for legacy values', () {
    expect(normalizeHardwareDecoder('nvdec'), defaultHardwareDecoder);
    expect(normalizeHardwareDecoder(null), defaultHardwareDecoder);
    expect(normalizeHardwareDecoder('d3d11va-copy'), 'd3d11va-copy');
  });
}
