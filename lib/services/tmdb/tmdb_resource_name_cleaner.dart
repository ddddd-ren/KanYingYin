class TmdbResourceNameCleaner {
  const TmdbResourceNameCleaner();

  static final RegExp _knownExtensionPattern = RegExp(
    r'\.(?:mp4|mkv|avi|mov|wmv|flv|webm|m4v|ts|m2ts|mts|mpg|mpeg|vob|rm|rmvb|3gp|asf|ogv|f4v|divx|mp3|flac|wav|aac|m4a|ogg|opus|wma|ape|alac|ac3|eac3|dts|mka|aiff|aif|amr|tak|tta|wv|dsf|dff)$',
    caseSensitive: false,
  );
  static final RegExp _releaseTokenPattern = RegExp(
    r'(?<![A-Za-z0-9])(?:'
    r'x26[45]|h[ ._-]*26[45]|avc|hevc|av1|vp9|vc[ ._-]*1|mpeg[ ._-]*2|xvid|divx|'
    r'web[ ._-]*dl|webrip|blu[ ._-]*ray|bdrip|remux|hdtv|dvdrip|bd|'
    r'dsnp|hbo[ ._-]*max|hami|tving|netflix|nf|kktv|hq|'
    r'hybrid|proper|2audio|black[ ._-]*tv|'
    r'2160p|1440p|1080[pi]|720p|480p|4k|8k|uhd|'
    r'(?:main)?(?:8|10|12)[ ._-]*bit|hi10p|'
    r'dolby[ ._-]*vision|dovi|hdr(?:10\+?)?|dv|hlg|sdr|'
    r'字幕组|字幕|中字|内嵌|内封|国配|台剧|美剧|日剧|韩剧|'
    r'dts(?:[ ._-]*hd(?:[ ._-]*ma)?)?(?:[ ._-]*(?:2[ .]0|5[ .]1|7[ .]1))?|'
    r'hd[ ._-]*ma|multi[ ._-]*audio|\d{1,2}[ ._-]*audio|'
    r'(?:true[ ._-]*hd|eac[ ._-]*3|ac[ ._-]*3|ddp|dd\+?|aac|flac|lpcm|pcm|opus|vorbis|wma|ape|alac)'
    r'(?:[ ._-]*(?:2[ .]0|5[ .]1|7[ .]1))?|atmos'
    r')(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  static final RegExp _bracketPattern = RegExp(r'\[([^\]]+)\]|【([^】]+)】');
  static final RegExp _seriesNumberPrefixPattern = RegExp(
    r'^\s*\d{6}_（系列）\s*',
    unicode: true,
  );
  static final RegExp _releaseSitePattern = RegExp(
    r'(?:高清剧集网|高清影视之家|(?:DD|PT|BT|QQ)HDTV\.com|SSDDSE\.com|发布\s+www\.)',
    caseSensitive: false,
  );
  static final RegExp _releaseDescriptionPattern = RegExp(
    r'(?:全\s*\d+\s*集|高码版|杜比视界版本|国语配音|国英双语|国粤多音轨|简繁英字幕|中文字幕|字幕|日剧)',
    caseSensitive: false,
  );
  static final RegExp _collectionSuffixPattern = RegExp(
    r'(?:剧场版\s*\d+\s*部|\d+\s*[-~至]\s*\d+\s*部合集|全集\s*4K\s*日语中字|全集|全\s*\d+\s*集)',
    caseSensitive: false,
  );
  static final RegExp _chineseReleasePhrasePattern = RegExp(
    r'(?:国语配音(?:\+字)?|国英双语|国粤多音轨|简繁英字幕|中文字幕|日语中字|高码版|珍藏版|杜比视界版本|原盘)',
    caseSensitive: false,
  );
  static final RegExp _languageTokenPattern = RegExp(
    r'(?<![A-Za-z0-9])(?:Eng|Fre|Ger|Ita|Por|Spa|Cze|Hun|Pol|Rus|Tha|Tur|Chi|Jpn)(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  static final RegExp _releaseGroupPattern = RegExp(
    r'(?:[-._ ](?:SGF|FGT|LeloveTV|BlackTV|DreamHD|HotWEB|ColorTV|ZeroTV|Huawei|Xiaomi|SSDSSE))\s*$',
    caseSensitive: false,
  );
  static final RegExp _releaseGroupNamePattern = RegExp(
    r'^(?:SGF|FGT|LeloveTV|BlackTV|DreamHD|HotWEB|ColorTV|ZeroTV|Huawei|Xiaomi)$',
    caseSensitive: false,
  );
  static final RegExp _remuxSuffixPattern = RegExp(
    r'(?<![A-Za-z0-9])(?:(?:v\d{1,2}|proper|us|uhd)[ ._-]+)*'
    r'remux(?=[ ._-]|$).*$',
    caseSensitive: false,
  );

  String clean(String value) {
    var result = value.trim().replaceFirst(_knownExtensionPattern, '');
    result = result.replaceFirst(_seriesNumberPrefixPattern, '');
    result = result.replaceAllMapped(_bracketPattern, (match) {
      final content = match.group(1) ?? match.group(2) ?? '';
      final isReleaseBlock = _releaseTokenPattern.hasMatch(content) ||
          _releaseSitePattern.hasMatch(content) ||
          _releaseDescriptionPattern.hasMatch(content) ||
          _releaseGroupNamePattern.hasMatch(content.trim());
      return isReleaseBlock ? ' ' : match.group(0)!;
    });
    return result
        .replaceAll(_collectionSuffixPattern, ' ')
        .replaceAll(_chineseReleasePhrasePattern, ' ')
        .replaceAll(_languageTokenPattern, ' ')
        .replaceAll(_remuxSuffixPattern, ' ')
        .replaceAll(_releaseGroupPattern, ' ')
        .replaceAll(_releaseTokenPattern, ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'^[\s&+,\-–—:：]+|[\s&+,\-–—:：]+$'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
