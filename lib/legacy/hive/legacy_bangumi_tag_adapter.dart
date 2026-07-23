import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/legacy/hive/legacy_bangumi_tag.dart';

/// 只为读取旧播放条目字段 9 保留已发布的 typeId 4。
final class LegacyBangumiTagAdapter extends TypeAdapter<LegacyBangumiTag> {
  @override
  final int typeId = 4;

  @override
  LegacyBangumiTag read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, Object?>{
      for (var index = 0; index < count; index++)
        reader.readByte(): reader.read(),
    };
    return LegacyBangumiTag(
      name: fields[0]?.toString() ?? '',
      count: fields[1] is num ? (fields[1] as num).toInt() : 0,
      totalCount: fields[2] is num ? (fields[2] as num).toInt() : 0,
    );
  }

  @override
  void write(BinaryWriter writer, LegacyBangumiTag value) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(value.name)
      ..writeByte(1)
      ..write(value.count)
      ..writeByte(2)
      ..write(value.totalCount);
  }
}
