import '../../models/exercise.dart';

/// The items of [exercise] in display order: shuffled with a seed derived
/// from the exercise id, so the same exercise always looks the same (also in
/// tests and across web / VM). Never the authoring order.
List<Option> shuffledItems(OrderExercise exercise) {
  final items = [...exercise.items];
  final random = _ParkMiller(_seedOf(exercise.id));
  // Fisher-Yates.
  for (var i = items.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final swap = items[i];
    items[i] = items[j];
    items[j] = swap;
  }
  final unchanged = [
    for (final (i, item) in items.indexed) item.id == exercise.items[i].id,
  ].every((same) => same);
  if (unchanged) {
    // Rotating distinct items always changes the order.
    items.add(items.removeAt(0));
  }
  return List.unmodifiable(items);
}

const _modulus = 2147483647; // 2^31 - 1

int _seedOf(String id) {
  var hash = 17;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) % _modulus;
  }
  return hash == 0 ? 1 : hash;
}

/// Minimal-standard PRNG; products stay below 2^53, so web gives the same
/// numbers as the VM (dart:math Random does not promise that).
class _ParkMiller {
  _ParkMiller(this._state);

  int _state;

  int nextInt(int max) {
    _state = (_state * 48271) % _modulus;
    return _state % max;
  }
}
