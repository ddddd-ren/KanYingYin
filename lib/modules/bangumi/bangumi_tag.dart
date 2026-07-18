import 'package:hive_ce/hive.dart';

part 'bangumi_tag.g.dart';

@HiveType(typeId: 4)
class BangumiTag {
  @HiveField(0)
  final String name;
  @HiveField(1)
  final int count;
  @HiveField(2)
  final int totalCount;

  BangumiTag({
    required this.name,
    required this.count,
    required this.totalCount,
  });

  factory BangumiTag.fromJson(Map<String, dynamic> json) {
    String optionalString(String field) {
      final value = json[field];
      if (value == null) return '';
      if (value is String) return value;
      throw FormatException('Bangumi 标签字段格式错误: $field');
    }

    int optionalInt(String field) {
      final value = json[field];
      if (value == null) return 0;
      if (value is int) return value;
      throw FormatException('Bangumi 标签字段格式错误: $field');
    }

    return BangumiTag(
      name: optionalString('name'),
      count: optionalInt('count'),
      totalCount: optionalInt('total_cont'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'count': count,
      'total_cont': totalCount,
    };
  }
}
