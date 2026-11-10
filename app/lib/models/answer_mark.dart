import 'exercise.dart';

/// UTF-16 offsets, matching Flutter's text selection offsets. These stay local;
/// the API uses the stable sentence ids covered by the marked text.
class AnswerMark {
  const AnswerMark(this.start, this.end) : assert(start >= 0 && end > start);
  final int start;
  final int end;
  @override
  bool operator ==(Object other) =>
      other is AnswerMark && start == other.start && end == other.end;
  @override
  int get hashCode => Object.hash(start, end);
}

String answerPassage(List<Sentence> sentences) =>
    sentences.map((s) => s.text).join();

AnswerMark sentenceMark(List<Sentence> sentences, int index) {
  if (index < 0 || index >= sentences.length) {
    throw ArgumentError.value(index, 'index');
  }
  final start = sentences
      .take(index)
      .fold<int>(0, (length, s) => length + s.text.length);
  return AnswerMark(start, start + sentences[index].text.length);
}

Set<int> markedIndexes(List<Sentence> sentences, Iterable<AnswerMark> marks) {
  final length = answerPassage(sentences).length;
  final indexes = <int>{};
  for (final mark in marks) {
    if (mark.start < 0 || mark.end > length || mark.end <= mark.start) {
      throw ArgumentError.value(mark, 'mark', 'outside the answer');
    }
    for (final sentence in sentences) {
      final bounds = sentenceMark(sentences, sentence.index);
      if (mark.start < bounds.end && mark.end > bounds.start) {
        indexes.add(sentence.index);
      }
    }
  }
  return indexes;
}
