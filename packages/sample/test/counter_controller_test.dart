import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_sample/src/counter/counter_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class CollectingEventLogger implements EventLogger {
  final records = <EventLogRecord>[];

  @override
  void log(EventLogRecord record) {
    records.add(record);
  }
}

void main() {
  test('dispatch applies counter events', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterIncremented(2));
    await container.read(counterProvider.notifier).dispatch(const CounterDecremented());

    expect(container.read(counterProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 1));
  });

  test('nested dispatch creates parent and child trace spans', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterResetThroughChild());

    final completed = logger.records.where((record) => record.phase == EventLogPhase.eventCompleted).toList();
    final parent = completed.singleWhere((record) => record.eventName == 'CounterResetThroughChild');
    final child = completed.singleWhere((record) => record.eventName == 'CounterReset');

    expect(child.traceContext.traceId, parent.traceContext.traceId);
    expect(child.traceContext.parentSpanId, parent.traceContext.spanId);
  });

  test('metadata and state labels are payload-free', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterIncremented(3));

    final transition = logger.records.singleWhere((record) => record.phase == EventLogPhase.transition);
    expect(transition.metadata, containsPair('amount', 3));
    expect(transition.previousStateLabel, 'count:0');
    expect(transition.nextStateLabel, 'count:3');
    expect(transition.stateMetadata, containsPair('changedBy', 3));
  });
}
