import 'package:blocpod_arch/src/observation_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fresh allocator starts at one and increments', () {
    final first = ObservationRuntime.capture();
    final second = ObservationRuntime.capture();

    expect(first.recordSequence, 1);
    expect(second.recordSequence, 2);
  });
}
