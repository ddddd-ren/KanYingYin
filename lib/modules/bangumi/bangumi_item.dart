import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/modules/bangumi/bangumi_tag.dart';

part 'bangumi_item.g.dart';

@HiveType(typeId: 0)
class BangumiItem {
  @HiveField(0)
  int id;
  @HiveField(1)
  int type;
  @HiveField(2)
  String name;
  @HiveField(3)
  String nameCn;
  @HiveField(4)
  String summary;
  @HiveField(5)
  String airDate;
  @HiveField(6)
  int airWeekday;
  @HiveField(7)
  int rank;
  @HiveField(8)
  Map<String, String> images;
  @HiveField(9, defaultValue: <BangumiTag>[])
  List<BangumiTag> tags;
  @HiveField(10, defaultValue: <String>[])
  List<String> alias;
  @HiveField(11, defaultValue: 0.0)
  double ratingScore;
  @HiveField(12, defaultValue: 0)
  int votes;
  @HiveField(13, defaultValue: <int>[])
  List<int> votesCount;
  @HiveField(14, defaultValue: '')
  String info;

  BangumiItem({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.airDate,
    required this.airWeekday,
    required this.rank,
    required this.images,
    required this.tags,
    required this.alias,
    required this.ratingScore,
    required this.votes,
    required this.votesCount,
    required this.info,
  });

  factory BangumiItem.fromJson(Map<String, dynamic> json) {
    FormatException invalidField(String field) =>
        FormatException('Bangumi 字段格式错误: $field');

    int requiredInt(String field) {
      final value = json[field];
      if (value is int) return value;
      throw invalidField(field);
    }

    int optionalInt(
      Map<String, dynamic> source,
      String field,
      int defaultValue,
    ) {
      final value = source[field];
      if (value == null) return defaultValue;
      if (value is int) return value;
      throw invalidField(field);
    }

    String optionalString(String field, [String defaultValue = '']) {
      final value = json[field];
      if (value == null) return defaultValue;
      if (value is String) return value;
      throw invalidField(field);
    }

    List<String> parseBangumiAliases(Map<String, dynamic> jsonData) {
      if (jsonData.containsKey('infobox') && jsonData['infobox'] is List) {
        final infobox = jsonData['infobox'];
        if (infobox is! List<Object?>) return [];
        for (var item in infobox) {
          if (item is Map<String, dynamic> && item['key'] == '别名') {
            final value = item['value'];
            if (value is List<Object?>) {
              return value
                  .map<String>((element) {
                    if (element is Map<String, dynamic> &&
                        element.containsKey('v')) {
                      return element['v'].toString();
                    }
                    return '';
                  })
                  .where((alias) => alias.isNotEmpty)
                  .toList();
            }
          }
        }
      }
      return [];
    }

    List<int> parseBangumiVoteCount(Map<String, dynamic> jsonData) {
      if (!jsonData.containsKey('rating')) {
        return [];
      }
      final rating = jsonData['rating'];
      if (rating is! Map<String, dynamic>) {
        return [];
      }
      final json = rating['count'];
      // For api.bgm.tv
      if (json is Map<String, dynamic>) {
        return List<int>.generate(10, (index) {
          final value = json['${index + 1}'];
          if (value is int) return value;
          throw invalidField('rating.count.${index + 1}');
        });
      }
      // For next.bgm.tv
      if (json is List<Object?>) {
        final values = <int>[];
        for (var index = 0; index < json.length; index++) {
          final value = json[index];
          if (value is! int) {
            throw invalidField('rating.count[$index]');
          }
          values.add(value);
        }
        return values;
      }
      return [];
    }

    final rawTags = json['tags'];
    if (rawTags != null && rawTags is! List<Object?>) {
      throw invalidField('tags');
    }
    final tags = rawTags as List<Object?>? ?? const <Object?>[];
    List<String> bangumiAlias = parseBangumiAliases(json);
    final tagList = <BangumiTag>[];
    for (var index = 0; index < tags.length; index++) {
      final tag = tags[index];
      if (tag is! Map<String, dynamic>) {
        throw invalidField('tags[$index]');
      }
      tagList.add(BangumiTag.fromJson(tag));
    }
    List<int> voteList = parseBangumiVoteCount(json);
    final rating = json['rating'];
    final ratingMap =
        rating is Map<String, dynamic> ? rating : <String, dynamic>{};
    final rawImages = json['images'];
    final imageMap = rawImages is Map<String, dynamic>
        ? rawImages.map((key, value) => MapEntry(key, value?.toString() ?? ''))
        : <String, String>{
            "large": optionalString('image'),
            "common": "",
            "medium": "",
            "small": "",
            "grid": ""
          };
    final airDate = (json['date'] ?? json['air_date'] ?? '').toString();
    final rawAirWeekday = json['air_weekday'];
    final airWeekday = rawAirWeekday is int &&
            rawAirWeekday >= DateTime.monday &&
            rawAirWeekday <= DateTime.sunday
        ? rawAirWeekday
        : _dateStringToWeekday(
            airDate.isEmpty ? '2000-11-11' : airDate,
          );
    final name = optionalString('name');
    final nameCn = optionalString('name_cn');
    final legacyNameCn = optionalString('nameCN');
    final score = ratingMap['score'];
    if (score != null && score is! num) {
      throw invalidField('rating.score');
    }
    return BangumiItem(
      id: requiredInt('id'),
      type: optionalInt(json, 'type', 2),
      name: name,
      nameCn: nameCn.isNotEmpty
          ? nameCn
          : legacyNameCn.isNotEmpty
              ? legacyNameCn
              : name,
      summary: optionalString('summary'),
      airDate: airDate,
      airWeekday: airWeekday,
      rank: optionalInt(ratingMap, 'rank', 0),
      images: Map<String, String>.from(imageMap),
      tags: tagList,
      alias: bangumiAlias,
      ratingScore: double.parse(
        (score as num? ?? 0.0).toDouble().toStringAsFixed(1),
      ),
      votes: optionalInt(ratingMap, 'total', 0),
      votesCount: voteList,
      info: optionalString('info'),
    );
  }
}

int _dateStringToWeekday(String dateString) {
  try {
    return DateTime.parse(dateString).weekday;
  } catch (_) {
    return DateTime.monday;
  }
}
