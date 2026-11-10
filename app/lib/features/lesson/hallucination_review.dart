import '../../models/answer.dart';
import '../../models/exercise.dart';

/// How one sentence of a checked hallucination exercise turned out.
enum SentenceVerdict {
  /// A wrong sentence the learner tapped.
  found,

  /// A wrong sentence the learner did not tap.
  missed,

  /// A correct sentence the learner tapped.
  falseAlarm,

  /// A correct sentence the learner left alone.
  untouched,
}

/// A sentence with its verdict; [error] is set exactly for wrong sentences.
class SentenceReview {
  const SentenceReview._(this.sentence, this.verdict, this.error);

  final Sentence sentence;
  final SentenceVerdict verdict;
  final HallucinationError? error;
}

/// A [HallucinationResult] resolved against its exercise: one entry per
/// sentence, in reading order.
class HallucinationReview {
  HallucinationReview._(List<SentenceReview> sentences)
    : sentences = List.unmodifiable(sentences);

  /// Throws [FormatException] when [result] does not fit [exercise]: an index
  /// outside the sentences, an error listed twice, or found / missed /
  /// falseAlarms that do not split the sentences consistently.
  factory HallucinationReview.resolve(
    HallucinationExercise exercise,
    HallucinationResult result,
  ) {
    final count = exercise.sentences.length;
    final errors = <int, HallucinationError>{};
    for (final error in result.errors) {
      if (error.index >= count || errors.containsKey(error.index)) {
        throw FormatException(
          'Result error index ${error.index} does not fit ${exercise.id}',
        );
      }
      errors[error.index] = error;
    }
    final found = _indexSet(result.found, count, 'found', exercise);
    final missed = _indexSet(result.missed, count, 'missed', exercise);
    final falseAlarms = _indexSet(
      result.falseAlarms,
      count,
      'falseAlarms',
      exercise,
    );
    final wrong = errors.keys.toSet();
    if (found.intersection(missed).isNotEmpty ||
        !found.union(missed).containsAll(wrong) ||
        !wrong.containsAll(found.union(missed)) ||
        falseAlarms.intersection(wrong).isNotEmpty) {
      throw FormatException('Result verdicts do not fit ${exercise.id}');
    }
    return HallucinationReview._([
      for (final sentence in exercise.sentences)
        SentenceReview._(
          sentence,
          found.contains(sentence.index)
              ? SentenceVerdict.found
              : missed.contains(sentence.index)
              ? SentenceVerdict.missed
              : falseAlarms.contains(sentence.index)
              ? SentenceVerdict.falseAlarm
              : SentenceVerdict.untouched,
          errors[sentence.index],
        ),
    ]);
  }

  /// Every sentence in reading order.
  final List<SentenceReview> sentences;

  /// The wrong sentences (found or missed), in reading order.
  Iterable<SentenceReview> get errors =>
      sentences.where((s) => s.error != null);

  int get errorCount => errors.length;

  int get foundCount =>
      sentences.where((s) => s.verdict == SentenceVerdict.found).length;

  Iterable<SentenceReview> get falseAlarms =>
      sentences.where((s) => s.verdict == SentenceVerdict.falseAlarm);

  static Set<int> _indexSet(
    List<int> indexes,
    int count,
    String field,
    HallucinationExercise exercise,
  ) {
    final set = indexes.toSet();
    if (set.length != indexes.length || set.any((i) => i >= count)) {
      throw FormatException('Result $field does not fit ${exercise.id}');
    }
    return set;
  }
}
