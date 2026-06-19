import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:blocpod_sample/src/counter/counter_controller.dart';
import 'package:blocpod_sample/src/logging/in_memory_log_sink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample log sink stores formatted Blocpod log entries', () async {
    final sink = InMemoryLogSink();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(BlocpodEventLogger(sink))]);
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterIncremented(1));

    expect(sink.entries, isNotEmpty);
    expect(sink.entries.map((entry) => entry.message), contains(contains('event.completed')));
    expect(sink.entries.map((entry) => entry.level), everyElement(BlocpodLogLevel.info));
    expect(sink.entries.last.metadata, containsPair('controllerName', 'SampleCounterController'));
  });
}
