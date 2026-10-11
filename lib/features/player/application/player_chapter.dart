class PlayerChapter {
  const PlayerChapter({
    required this.index,
    required this.position,
    required this.title,
  });

  factory PlayerChapter.fromMpvValues({
    required int index,
    required String title,
    required String time,
  }) {
    final seconds = double.tryParse(time.trim());
    if (seconds == null || !seconds.isFinite || seconds < 0) {
      throw const FormatException('章节时间无效');
    }
    return PlayerChapter(
      index: index,
      position: Duration(milliseconds: (seconds * 1000).round()),
      title: title.trim().isEmpty ? '第 ${index + 1} 章' : title.trim(),
    );
  }

  final int index;
  final Duration position;
  final String title;
}
