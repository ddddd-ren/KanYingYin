import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/services/cloud/cloud_media_path_parser.dart';

class CloudMediaGroupingMetadata {
  CloudMediaGroupingMetadata._();

  static final CloudMediaPathParser _pathParser = CloudMediaPathParser();

  static int? seasonNumber(CloudMediaIndexItem item) {
    final indexedSeason = item.seasonNumber;
    if (indexedSeason != null && indexedSeason > 0) return indexedSeason;
    final parsedSeason = _pathParser.parse(item.remotePath).seasonNumber;
    return parsedSeason != null && parsedSeason > 0 ? parsedSeason : null;
  }
}
