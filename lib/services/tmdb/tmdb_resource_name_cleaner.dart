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
    r'dsnp|hbo[ ._-]*max|black[ ._-]*tv|'
    r'2160p|1440p|1080[pi]|720p|480p|4k|8k|uhd|'
    r'dolby[ ._-]*vision|hdr(?:10\+?)?|dv|hlg|sdr|'
    r'字幕组|字幕|中字|内嵌|内封|国配|台剧|美剧|日剧|韩剧|'
    r'dts(?:[ ._-]*hd(?:[ ._-]*ma)?)?(?:[ ._-]*(?:2\.0|5\.1|7\.1))?|'
    r'(?:true[ ._-]*hd|eac[ ._-]*3|ac[ ._-]*3|ddp|dd\+?|aac|flac|lpcm|pcm|opus|vorbis|wma|ape|alac)'
    r'(?:[ ._-]*(?:2\.0|5\.1|7\.1))?|atmos'
    r')(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  static final RegExp _bracketPattern = RegExp(r'\[([^\]]+)\]|【([^】]+)】');

  String clean(String value) {
    var result = value.trim().replaceFirst(_knownExtensionPattern, '');
    result = result.replaceAllMapped(_bracketPattern, (match) {
      final content = match.group(1) ?? match.group(2) ?? '';
      return _releaseTokenPattern.hasMatch(content) ? ' ' : match.group(0)!;
    });
    return result
        .replaceAll(_releaseTokenPattern, ' ')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'^[\s&+,\-–—:：]+|[\s&+,\-–—:：]+$'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
