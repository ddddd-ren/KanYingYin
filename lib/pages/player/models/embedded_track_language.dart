enum EmbeddedTrackType { audio, subtitle }

enum TrackLanguageKind {
  mandarin,
  cantonese,
  taiwaneseMandarin,
  simplifiedChinese,
  bilingualChinese,
  traditionalChinese,
  english,
  japanese,
  korean,
  other,
  unknown,
}

enum TrackLanguageSource { metadata, title, user, unresolved }

class TrackLanguageChoice {
  const TrackLanguageChoice({
    required this.code,
    required this.label,
    required this.kind,
    required this.source,
  });

  final String code;
  final String label;
  final TrackLanguageKind kind;
  final TrackLanguageSource source;

  bool get isResolved => source != TrackLanguageSource.unresolved;

  TrackLanguageChoice confirmedByUser() => TrackLanguageChoice(
        code: code,
        label: label,
        kind: kind,
        source: TrackLanguageSource.user,
      );
}

class PendingTrackLanguage {
  const PendingTrackLanguage({
    required this.fingerprint,
    required this.type,
    required this.trackId,
    required this.codecLabel,
    required this.title,
  });

  final String fingerprint;
  final EmbeddedTrackType type;
  final String trackId;
  final String codecLabel;
  final String title;
}

class TrackLanguageConfirmationState {
  int _revision = 0;
  String _mediaKey = '';

  int begin(String mediaKey, List<PendingTrackLanguage> pending) {
    _mediaKey = mediaKey;
    return ++_revision;
  }

  bool canApply(int revision, String mediaKey) =>
      revision == _revision && mediaKey == _mediaKey;

  void reset() {
    _mediaKey = '';
    _revision++;
  }
}

const commonTrackLanguageChoices = <TrackLanguageChoice>[
  TrackLanguageChoice(
    code: 'zh-Hans',
    label: '简体中文',
    kind: TrackLanguageKind.simplifiedChinese,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'zh-Hant',
    label: '繁体中文',
    kind: TrackLanguageKind.traditionalChinese,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'zh-bilingual',
    label: '简繁双语',
    kind: TrackLanguageKind.bilingualChinese,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'zh',
    label: '国语 / Mandarin',
    kind: TrackLanguageKind.mandarin,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'yue',
    label: '粤语 / Cantonese',
    kind: TrackLanguageKind.cantonese,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'zh-TW',
    label: '台配',
    kind: TrackLanguageKind.taiwaneseMandarin,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'en',
    label: '英语 / English',
    kind: TrackLanguageKind.english,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'ja',
    label: '日语',
    kind: TrackLanguageKind.japanese,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'ko',
    label: '韩语',
    kind: TrackLanguageKind.korean,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'fr',
    label: '法语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'de',
    label: '德语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'es',
    label: '西班牙语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'pt',
    label: '葡萄牙语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'ru',
    label: '俄语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'it',
    label: '意大利语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'ar',
    label: '阿拉伯语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'th',
    label: '泰语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.metadata,
  ),
  TrackLanguageChoice(
    code: 'vi',
    label: '越南语',
    kind: TrackLanguageKind.other,
    source: TrackLanguageSource.metadata,
  ),
];

TrackLanguageChoice trackLanguageFromMetadata(
  String? language,
  String? title, {
  required EmbeddedTrackType type,
}) {
  final languageText = language?.trim().toLowerCase() ?? '';
  final titleText = title?.trim().toLowerCase() ?? '';
  final source = '$languageText $titleText';

  TrackLanguageChoice choice(String code, String label, TrackLanguageKind kind,
      TrackLanguageSource source) {
    return TrackLanguageChoice(
      code: code,
      label: label,
      kind: kind,
      source: source,
    );
  }

  if (_containsAny(source, const ['粤语', '广东话', 'cantonese', 'yue'])) {
    return choice('yue', '粤语 / Cantonese', TrackLanguageKind.cantonese,
        _sourceOf(languageText, titleText));
  }
  if (_containsAny(source, const ['台配', '台湾国语'])) {
    return choice('zh-TW', '台配', TrackLanguageKind.taiwaneseMandarin,
        _sourceOf(languageText, titleText));
  }
  if (type == EmbeddedTrackType.subtitle) {
    if (_containsAny(source, const ['简繁', '双语'])) {
      return choice('zh-bilingual', '简繁双语', TrackLanguageKind.bilingualChinese,
          _sourceOf(languageText, titleText));
    }
    if (_containsAny(source, const ['繁体', '繁中', 'traditional', 'zh-hant'])) {
      return choice('zh-Hant', '繁体中文', TrackLanguageKind.traditionalChinese,
          _sourceOf(languageText, titleText));
    }
    if (_containsAny(
        source, const ['简体', '简中', 'simplified', 'zh-hans', 'chs'])) {
      return choice('zh-Hans', '简体中文', TrackLanguageKind.simplifiedChinese,
          _sourceOf(languageText, titleText));
    }
  }
  if (_matchesCode(languageText, const ['zh', 'zho', 'chi', 'zh-cn']) ||
      _containsAny(source, const ['中文', '国语', '普通话', 'mandarin'])) {
    return choice(
      type == EmbeddedTrackType.audio ? 'zh' : 'zh-Hans',
      type == EmbeddedTrackType.audio ? '国语 / Mandarin' : '简体中文',
      type == EmbeddedTrackType.audio
          ? TrackLanguageKind.mandarin
          : TrackLanguageKind.simplifiedChinese,
      _sourceOf(languageText, titleText),
    );
  }
  if (_matchesCode(languageText, const ['en', 'eng']) ||
      _containsAny(source, const ['english', '英语'])) {
    return choice(
      'en',
      '英语 / English',
      TrackLanguageKind.english,
      _sourceOf(languageText, titleText),
    );
  }
  if (_matchesCode(languageText, const ['ja', 'jpn']) ||
      _containsAny(source, const ['japanese', '日本語', '日语'])) {
    return choice(
      'ja',
      '日语',
      TrackLanguageKind.japanese,
      _sourceOf(languageText, titleText),
    );
  }
  if (_matchesCode(languageText, const ['ko', 'kor']) ||
      _containsAny(source, const ['korean', '한국어', '韩语'])) {
    return choice(
      'ko',
      '韩语',
      TrackLanguageKind.korean,
      _sourceOf(languageText, titleText),
    );
  }

  const titleLabels = <String, (String, String)>{
    'french': ('fr', '法语'),
    '法语': ('fr', '法语'),
    'german': ('de', '德语'),
    '德语': ('de', '德语'),
    'spanish': ('es', '西班牙语'),
    '西班牙语': ('es', '西班牙语'),
    'portuguese': ('pt', '葡萄牙语'),
    '葡萄牙语': ('pt', '葡萄牙语'),
    'russian': ('ru', '俄语'),
    '俄语': ('ru', '俄语'),
    'italian': ('it', '意大利语'),
    '意大利语': ('it', '意大利语'),
    'arabic': ('ar', '阿拉伯语'),
    '阿拉伯语': ('ar', '阿拉伯语'),
    'thai': ('th', '泰语'),
    '泰语': ('th', '泰语'),
    'vietnamese': ('vi', '越南语'),
    '越南语': ('vi', '越南语'),
  };
  for (final entry in titleLabels.entries) {
    if (titleText.contains(entry.key)) {
      return choice(
        entry.value.$1,
        entry.value.$2,
        TrackLanguageKind.other,
        TrackLanguageSource.title,
      );
    }
  }

  const codeLabels = <String, (String, String)>{
    'fr': ('fr', '法语'),
    'fra': ('fr', '法语'),
    'fre': ('fr', '法语'),
    'de': ('de', '德语'),
    'deu': ('de', '德语'),
    'ger': ('de', '德语'),
    'es': ('es', '西班牙语'),
    'spa': ('es', '西班牙语'),
    'pt': ('pt', '葡萄牙语'),
    'por': ('pt', '葡萄牙语'),
    'ru': ('ru', '俄语'),
    'rus': ('ru', '俄语'),
    'it': ('it', '意大利语'),
    'ita': ('it', '意大利语'),
    'ar': ('ar', '阿拉伯语'),
    'ara': ('ar', '阿拉伯语'),
    'th': ('th', '泰语'),
    'tha': ('th', '泰语'),
    'vi': ('vi', '越南语'),
    'vie': ('vi', '越南语'),
  };
  for (final entry in codeLabels.entries) {
    if (_matchesCode(languageText, [entry.key])) {
      return choice(
        entry.value.$1,
        entry.value.$2,
        TrackLanguageKind.other,
        TrackLanguageSource.metadata,
      );
    }
  }

  return const TrackLanguageChoice(
    code: '',
    label: '',
    kind: TrackLanguageKind.unknown,
    source: TrackLanguageSource.unresolved,
  );
}

bool _matchesCode(String value, List<String> codes) {
  if (value.isEmpty) return false;
  final normalized = value.replaceAll('_', '-');
  return codes
      .any((code) => normalized == code || normalized.startsWith('$code-'));
}

bool _containsAny(String value, List<String> candidates) =>
    candidates.any(value.contains);

TrackLanguageSource _sourceOf(String language, String title) =>
    language.isNotEmpty
        ? TrackLanguageSource.metadata
        : title.isNotEmpty
            ? TrackLanguageSource.title
            : TrackLanguageSource.metadata;
