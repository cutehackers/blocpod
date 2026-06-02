import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlocpodEventLogger', () {
    test('maps EventLogRecord into BlocpodLogEntry', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final record = eventRecord();

      logger.log(record);

      expect(sink.entries, hasLength(1));

      final entry = sink.entries.single;
      expect(entry.level, BlocpodLogLevel.info);
      expect(entry.message, 'CounterController IncrementEvent eventCompleted loading->data 12ms');
      expect(entry.timestamp, record.startedAt);
      expect(entry.metadata, <String, Object?>{
        'phase': 'eventCompleted',
        'traceId': record.traceContext.traceId,
        'spanId': record.traceContext.spanId,
        'parentSpanId': record.traceContext.parentSpanId,
        'controllerName': 'CounterController',
        'eventName': 'IncrementEvent',
        'durationMicros': 12000,
        'previousStateKind': 'loading',
        'nextStateKind': 'data',
        'hasChanged': true,
        'feature': 'counter',
      });
      expect(entry.error, isNull);
      expect(entry.stackTrace, isNull);
    });

    test('preserves reserved bridge metadata on caller collisions', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final record = eventRecord(
        transitionIndex: 2,
        previousStateLabel: 'ready',
        nextStateLabel: 'saving',
        stateMetadata: const <String, Object?>{'status': 'busy'},
        metadata: const <String, Object?>{
          'phase': 'wrong-phase',
          'traceId': 'wrong-trace',
          'spanId': 'wrong-span',
          'parentSpanId': 'wrong-parent',
          'controllerName': 'WrongController',
          'eventName': 'WrongEvent',
          'durationMicros': -1,
          'transitionIndex': -1,
          'previousStateKind': 'wrong-previous-kind',
          'nextStateKind': 'wrong-next-kind',
          'hasChanged': false,
          'previousStateLabel': 'wrong-previous-label',
          'nextStateLabel': 'wrong-next-label',
          'stateMetadata': <String, Object?>{'status': 'wrong'},
          'feature': 'counter',
        },
      );

      logger.log(record);

      final metadata = sink.entries.single.metadata;
      expect(metadata['phase'], 'eventCompleted');
      expect(metadata['traceId'], record.traceContext.traceId);
      expect(metadata['spanId'], record.traceContext.spanId);
      expect(metadata['parentSpanId'], record.traceContext.parentSpanId);
      expect(metadata['controllerName'], 'CounterController');
      expect(metadata['eventName'], 'IncrementEvent');
      expect(metadata['durationMicros'], 12000);
      expect(metadata['transitionIndex'], 2);
      expect(metadata['previousStateKind'], 'loading');
      expect(metadata['nextStateKind'], 'data');
      expect(metadata['hasChanged'], true);
      expect(metadata['previousStateLabel'], 'ready');
      expect(metadata['nextStateLabel'], 'saving');
      expect(metadata['stateMetadata'], <String, Object?>{'status': 'busy'});
      expect(metadata['feature'], 'counter');
    });

    test('drops fake parent span metadata for root spans', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final record = eventRecord(
        useRootTraceContext: true,
        metadata: const <String, Object?>{'parentSpanId': 'fake', 'feature': 'counter'},
      );

      logger.log(record);

      final metadata = sink.entries.single.metadata;
      expect(record.traceContext.parentSpanId, isNull);
      expect(metadata.containsKey('parentSpanId') ? metadata['parentSpanId'] : null, isNull);
      expect(metadata['feature'], 'counter');
    });

    test('maps transition records with transition index and state summaries', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final record = eventRecord(
        phase: EventLogPhase.transition,
        duration: null,
        transitionIndex: 2,
        previousStateLabel: 'ready',
        nextStateLabel: 'saving',
        stateMetadata: const <String, Object?>{'status': 'busy'},
      );

      logger.log(record);

      final entry = sink.entries.single;
      expect(entry.message, 'CounterController IncrementEvent transition#2 loading->data');
      expect(entry.metadata, containsPair('phase', 'transition'));
      expect(entry.metadata, containsPair('transitionIndex', 2));
      expect(entry.metadata, containsPair('previousStateLabel', 'ready'));
      expect(entry.metadata, containsPair('nextStateLabel', 'saving'));
      expect(entry.metadata, containsPair('stateMetadata', <String, Object?>{'status': 'busy'}));
      expect(entry.metadata.containsKey('durationMicros'), isFalse);
    });

    test('maps error records to error-level entries', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final error = StateError('boom');
      final stackTrace = StackTrace.current;
      final record = eventRecord(error: error, stackTrace: stackTrace);

      logger.log(record);

      final entry = sink.entries.single;
      expect(entry.level, BlocpodLogLevel.error);
      expect(entry.error, same(error));
      expect(entry.stackTrace, same(stackTrace));
    });

    test('isolates sink failures', () {
      final logger = BlocpodEventLogger(ThrowingLogSink());

      expect(() => logger.log(eventRecord()), returnsNormally);
    });
  });
}

final class MemoryLogSink implements BlocpodLogSink {
  final List<BlocpodLogEntry> entries = <BlocpodLogEntry>[];

  @override
  void write(BlocpodLogEntry entry) {
    entries.add(entry);
  }
}

final class ThrowingLogSink implements BlocpodLogSink {
  @override
  void write(BlocpodLogEntry entry) {
    throw StateError('sink failed');
  }
}

EventLogRecord eventRecord({
  EventLogPhase phase = EventLogPhase.eventCompleted,
  Object? error,
  StackTrace? stackTrace,
  Map<String, Object?> metadata = const <String, Object?>{'feature': 'counter'},
  bool useRootTraceContext = false,
  Duration? duration = const Duration(milliseconds: 12),
  int? transitionIndex,
  String? previousStateLabel,
  String? nextStateLabel,
  Map<String, Object?> stateMetadata = const <String, Object?>{},
}) {
  final startedAt = DateTime.utc(2026, 6, 1, 9, 30);
  final rootTraceContext = TraceContext.root(startedAt: startedAt.subtract(const Duration(milliseconds: 1)));
  final traceContext = useRootTraceContext ? rootTraceContext : rootTraceContext.child(startedAt: startedAt);

  return EventLogRecord(
    phase: phase,
    traceContext: traceContext,
    controllerName: 'CounterController',
    eventName: 'IncrementEvent',
    startedAt: startedAt,
    duration: duration,
    transitionIndex: transitionIndex,
    previousStateKind: AsyncValueKind.loading,
    nextStateKind: AsyncValueKind.data,
    hasChanged: true,
    previousStateLabel: previousStateLabel,
    nextStateLabel: nextStateLabel,
    stateMetadata: stateMetadata,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
  );
}
