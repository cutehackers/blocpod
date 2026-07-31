import 'package:blocpod_arch/src/observation_occurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isolate-local occurrence sequence starts at one and increments', () {
    final first = ObservationOccurrence.capture();
    final second = ObservationOccurrence.capture();

    expect(first.recordSequence, 1);
    expect(second.recordSequence, 2);
  });
}
