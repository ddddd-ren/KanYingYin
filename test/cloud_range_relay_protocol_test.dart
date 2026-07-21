import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/range/cloud_range_relay_protocol.dart';

void main() {
  group('parseSingleHttpRange', () {
    test('解析完整、开放结尾和后缀区间', () {
      expect(parseSingleHttpRange('bytes=0-15', 100), const ByteRange(0, 15));
      expect(parseSingleHttpRange('bytes=16-', 100), const ByteRange(16, 99));
      expect(parseSingleHttpRange('bytes=-16', 100), const ByteRange(84, 99));
    });

    test('将超出文件结尾的区间收窄到最后一个字节', () {
      expect(
          parseSingleHttpRange('bytes=90-120', 100), const ByteRange(90, 99));
    });

    test('拒绝多区间、倒序、越界、空文件和非法单位', () {
      for (final value in <String>[
        'bytes=0-1,4-5',
        'bytes=10-9',
        'bytes=100-',
        'bytes=-0',
        'items=0-1',
        'bytes=',
      ]) {
        expect(
          () => parseSingleHttpRange(value, 100),
          throwsA(isA<RangeNotSatisfiable>()),
          reason: value,
        );
      }
      expect(
        () => parseSingleHttpRange('bytes=0-1', 0),
        throwsA(isA<RangeNotSatisfiable>()),
      );
    });
  });

  test('ByteRange 生成标准 Content-Range 与长度', () {
    const range = ByteRange(16, 31);
    expect(range.length, 16);
    expect(range.contentRange(100), 'bytes 16-31/100');
    expect(const RangeNotSatisfiable(100).contentRange, 'bytes */100');
  });
}
