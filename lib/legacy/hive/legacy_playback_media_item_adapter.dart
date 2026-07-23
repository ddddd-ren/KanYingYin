import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/modules/video/playback_media_item.dart';

/// 读取已发布 typeId 0 的旧二进制数据，并映射为中性播放媒体条目。
final class LegacyPlaybackMediaItemAdapter
    extends TypeAdapter<PlaybackMediaItem> {
  @override
  final int typeId = 0;

  @override
  PlaybackMediaItem read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, Object?>{
      for (var index = 0; index < count; index++)
        reader.readByte(): reader.read(),
    };
    final images = fields[8];
    final artwork = images is Map ? images['large']?.toString() : null;
    return PlaybackMediaItem(
      id: fields[0] is num ? (fields[0] as num).toInt() : 0,
      title: fields[2]?.toString() ?? '',
      displayTitle: fields[3]?.toString() ?? fields[2]?.toString() ?? '',
      summary: fields[4]?.toString() ?? '',
      artworkUrl: artwork?.trim().isEmpty == true ? null : artwork,
    );
  }

  @override
  void write(BinaryWriter writer, PlaybackMediaItem value) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(value.id)
      ..writeByte(2)
      ..write(value.title)
      ..writeByte(3)
      ..write(value.displayTitle)
      ..writeByte(4)
      ..write(value.summary)
      ..writeByte(8)
      ..write(<String, String>{
        if (value.artworkUrl != null) 'large': value.artworkUrl!,
      });
  }
}
