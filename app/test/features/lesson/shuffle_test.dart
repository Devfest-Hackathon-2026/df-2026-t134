import 'package:ailearn/features/lesson/shuffle.dart';
import 'package:ailearn/models/exercise.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/unit1.dart';

void main() {
  final orderExercises = unit1.exercises.whereType<OrderExercise>().toList();

  test('Unit 1 has order exercises to check', () {
    expect(orderExercises, isNotEmpty);
  });

  test('is a permutation that differs from the authoring order', () {
    for (final exercise in orderExercises) {
      final shuffled = shuffledItems(exercise).map((i) => i.id).toList();
      final authored = exercise.items.map((i) => i.id).toList();

      expect(shuffled.toSet(), authored.toSet(), reason: exercise.id);
      expect(shuffled, hasLength(authored.length));
      expect(shuffled, isNot(authored), reason: exercise.id);
    }
  });

  test('is the same every time for the same exercise', () {
    final exercise = orderExercises.first;

    expect(
      shuffledItems(exercise).map((i) => i.id),
      shuffledItems(exercise).map((i) => i.id),
    );
  });

  test('two items are always swapped', () {
    const exercise = OrderExercise(
      id: 'x-q1',
      lessonId: 'x',
      question: 'q',
      items: [
        Option(id: 'one', text: '1'),
        Option(id: 'two', text: '2'),
      ],
    );

    expect(shuffledItems(exercise).map((i) => i.id), ['two', 'one']);
  });
}
