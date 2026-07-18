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
        return List<int>.generate(10, (i) => json['${i + 1}'] as int);
      }
      // For next.bgm.tv
      if (json is List<Object?>) {
        return json.whereType<int>().toList();
      }
      return [];
    }

    final rawTags = json['tags'];
    final tags = rawTags is List<Object?> ? rawTags : const <Object?>[];
    List<String> bangumiAlias = parseBangumiAliases(json);
    final tagList = tags
        .whereType<Map<String, dynamic>>()
        .map(BangumiTag.fromJson)
        .toList();
    List<int> voteList = parseBangumiVoteCount(json);
    final rating = json['rating'];
    final ratingMap =
        rating is Map<String, dynamic> ? rating : <String, dynamic>{};
    final rawImages = json['images'];
    final imageMap = rawImages is Map<String, dynamic>
        ? rawImages.map((key, value) => MapEntry(key, value?.toString() ?? ''))
        : <String, String>{
            "large": json['image']?.toString() ?? '',
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
    return BangumiItem(
      id: json['id'] is int ? json['id'] as int : 0,
      type: json['type'] is int ? json['type'] as int : 2,
      name: json['name']?.toString() ?? '',
      nameCn: (json['name_cn'] ?? '') == ''
          ? (((json['nameCN'] ?? '') == '')
              ? json['name']?.toString() ?? ''
              : json['nameCN']?.toString() ?? '')
          : json['name_cn']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      airDate: airDate,
      airWeekday: airWeekday,
      rank: ratingMap['rank'] is int ? ratingMap['rank'] as int : 0,
      images: Map<String, String>.from(imageMap),
      tags: tagList,
      alias: bangumiAlias,
      ratingScore: double.parse(
        (ratingMap['score'] is num ? ratingMap['score'] as num : 0.0)
            .toDouble()
            .toStringAsFixed(1),
      ),
      votes: ratingMap['total'] is int ? ratingMap['total'] as int : 0,
      votesCount: voteList,
      info: json['info']?.toString() ?? '',
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
