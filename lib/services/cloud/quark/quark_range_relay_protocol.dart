class ByteRange {
  const ByteRange(this.start, this.endInclusive)
      : assert(start >= 0),
        assert(endInclusive >= start);

  final int start;
  final int endInclusive;

  int get length => endInclusive - start + 1;

  String contentRange(int totalLength) =>
      'bytes $start-$endInclusive/$totalLength';

  @override
  bool operator ==(Object other) =>
      other is ByteRange &&
      other.start == start &&
      other.endInclusive == endInclusive;

  @override
  int get hashCode => Object.hash(start, endInclusive);

  @override
  String toString() => 'ByteRange($start, $endInclusive)';
}

class RangeNotSatisfiable implements Exception {
  const RangeNotSatisfiable(this.totalLength) : assert(totalLength >= 0);

  final int totalLength;

  String get contentRange => 'bytes */$totalLength';

  @override
  String toString() => 'RangeNotSatisfiable(totalLength: $totalLength)';
}

ByteRange parseSingleHttpRange(String value, int totalLength) {
  if (totalLength <= 0) {
    throw RangeNotSatisfiable(totalLength < 0 ? 0 : totalLength);
  }
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value.trim());
  if (match == null) throw RangeNotSatisfiable(totalLength);

  final startText = match.group(1)!;
  final endText = match.group(2)!;
  if (startText.isEmpty && endText.isEmpty) {
    throw RangeNotSatisfiable(totalLength);
  }

  if (startText.isEmpty) {
    final suffixLength = int.tryParse(endText);
    if (suffixLength == null || suffixLength <= 0) {
      throw RangeNotSatisfiable(totalLength);
    }
    final start = suffixLength >= totalLength ? 0 : totalLength - suffixLength;
    return ByteRange(start, totalLength - 1);
  }

  final start = int.tryParse(startText);
  if (start == null || start >= totalLength) {
    throw RangeNotSatisfiable(totalLength);
  }
  if (endText.isEmpty) return ByteRange(start, totalLength - 1);

  final requestedEnd = int.tryParse(endText);
  if (requestedEnd == null || requestedEnd < start) {
    throw RangeNotSatisfiable(totalLength);
  }
  final end = requestedEnd >= totalLength ? totalLength - 1 : requestedEnd;
  return ByteRange(start, end);
}
