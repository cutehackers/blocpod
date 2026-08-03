import 'dart:convert';

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
    final container = ProviderContainer(
      overrides: [
        eventLoggerProvider.overrideWithValue(
          BlocpodEventLogger(sink, formatter: const PrettyEventLogRecordFormatter()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterIncremented(1));

    expect(sink.entries, isNotEmpty);
    expect(
      sink.entries.map((entry) => entry.message),
      contains(
        matches(
          RegExp(
            r'^✅ SampleCounterController · CounterIncremented completed data\(count:0\) → '
            r'data\(count:1\) in (\d+µs|\d+ms|\d+(?:\.\d{1,2})?s)$',
          ),
        ),
      ),
    );
    expect(sink.entries.map((entry) => entry.level), everyElement(BlocpodLogLevel.info));
    expect(sink.entries.last.attributes, containsPair('controllerName', 'SampleCounterController'));
    expect(sink.entries.last.sequence, isNotNull);
  });

  test('sample log sink entries encode as ordered JSON lines', () async {
    final sink = InMemoryLogSink();
    final container = ProviderContainer(
      overrides: [
        eventLoggerProvider.overrideWithValue(
          BlocpodEventLogger(sink, formatter: const PrettyEventLogRecordFormatter()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterIncremented(1));

    final lines = sink.entries.map(const JsonLogEncoder().encode).toList();
    final decoded = lines.map((line) => jsonDecode(line) as Map<String, Object?>).toList();

    expect(lines, everyElement(isNot(contains('\n'))));
    expect(decoded, everyElement(containsPair('schema', 'blocpod.log')));

    final sequences = decoded.map((json) => json['sequence']! as int).toList();
    expect(sequences, orderedEquals(<int>[...sequences]..sort()));
    expect(
      decoded.map((json) => (json['attributes']! as Map<String, Object?>)['phase']),
      containsAllInOrder(<String>['event.started', 'state.transition', 'event.completed']),
    );
  });

  test('encoder failure does not change the dispatch result', () async {
    final sink = DebugPrintLogSink(encoder: const ThrowingEncoder(), debugPrintOverride: (message, {wrapWidth}) {});
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(BlocpodEventLogger(sink))]);
    addTearDown(container.dispose);

    await expectLater(container.read(counterProvider.notifier).dispatch(const CounterIncremented(1)), completes);
    expect(container.read(counterProvider).value, 1);
  });
}

final class ThrowingEncoder implements BlocpodLogEncoder {
  const ThrowingEncoder();

  @override
  String encode(BlocpodLogEntry entry) => throw StateError('encoder failed');
}
