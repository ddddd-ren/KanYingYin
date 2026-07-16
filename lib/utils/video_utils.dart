class VideoUtils {
  static String decodeVideoSource(String iframeUrl) {
    var decodedUrl = Uri.decodeFull(iframeUrl);
    RegExp regExp = RegExp(r'(http[s]?://.*?\.m3u8)|(http[s]?://.*?\.mp4)',
        caseSensitive: false);

    Uri uri = Uri.parse(decodedUrl);
    Map<String, String> params = uri.queryParameters;

    String matchedUrl = iframeUrl;
    params.forEach((key, value) {
      if (regExp.hasMatch(value)) {
        matchedUrl = value;
        return;
      }
    });

    return Uri.encodeFull(matchedUrl);
  }

  static int extractEpisodeNumber(String input) {
    RegExp regExp = RegExp(r'第?(\d+)[话集]?');
    Match? match = regExp.firstMatch(input);

    if (match != null && match.group(1) != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }

    return 0;
  }

  static String formatTraceSimilarity(double? similarity,
      {int fractionDigits = 1, String empty = '--'}) {
    if (similarity == null) {
      return empty;
    }
    return '${(similarity * 100).toStringAsFixed(fractionDigits)}%';
  }
}
