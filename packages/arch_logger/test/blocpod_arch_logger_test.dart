import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BlocpodEventLogger', () {
    test('accepts any Blocpod event log formatter implementation', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink, formatter: const StubEventLogFormatter());

      logger.log(eventRecord());

      expect(sink.entries, hasLength(1));
      expect(sink.entries.single.message, 'stub formatted');
      expect(sink.entries.single.metadata, containsPair('formatter', 'stub'));
    });

    test('maps EventLogRecord into BlocpodLogEntry', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final record = eventRecord();

      logger.log(record);

      expect(sink.entries, hasLength(1));

      final entry = sink.entries.single;
      expect(entry.level, BlocpodLogLevel.info);
      expect(entry.message, 'CounterController IncrementEvent event.completed loading->data 12ms');
      expect(entry.timestamp, record.startedAt);
      expect(entry.metadata, <String, Object?>{
        'phase': 'event.completed',
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
      expect(metadata['phase'], 'event.completed');
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
      expect(entry.message, 'CounterController IncrementEvent state.transition#2 loading->data');
      expect(entry.metadata, containsPair('phase', 'state.transition'));
      expect(entry.metadata, containsPair('transitionIndex', 2));
      expect(entry.metadata, containsPair('previousStateLabel', 'ready'));
      expect(entry.metadata, containsPair('nextStateLabel', 'saving'));
      expect(entry.metadata, containsPair('stateMetadata', <String, Object?>{'status': 'busy'}));
      expect(entry.metadata.containsKey('durationMicros'), isFalse);
    });

    test('compact formatter uses log-friendly phase labels and keeps hasChanged', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final record = eventRecord(
        phase: EventLogPhase.transition,
        duration: null,
        transitionIndex: 1,
        previousStateLabel: 'count:0',
        nextStateLabel: 'count:1',
        stateMetadata: const <String, Object?>{'changedBy': 1},
      );

      logger.log(record);

      final entry = sink.entries.single;
      expect(entry.message, 'CounterController IncrementEvent state.transition#1 loading->data');
      final metadata = sink.entries.single.metadata;
      expect(metadata, containsPair('hasChanged', true));
      expect(metadata, containsPair('phase', 'state.transition'));
      expect(metadata, containsPair('previousStateLabel', 'count:0'));
      expect(metadata, containsPair('nextStateLabel', 'count:1'));
      expect(metadata, containsPair('stateMetadata', <String, Object?>{'changedBy': 1}));
    });

    test('event phase labels are optimized for log scanning', () {
      expect(eventLogPhaseLabel(EventLogPhase.controllerCreated), 'controller.created');
      expect(eventLogPhaseLabel(EventLogPhase.eventStarted), 'event.started');
      expect(eventLogPhaseLabel(EventLogPhase.transition), 'state.transition');
      expect(eventLogPhaseLabel(EventLogPhase.eventCompleted), 'event.completed');
      expect(eventLogPhaseLabel(EventLogPhase.eventFailed), 'event.failed');
      expect(eventLogPhaseLabel(EventLogPhase.controllerDisposed), 'controller.disposed');
    });

    test('pretty formatter renders transition as the canonical Blocpod state-assignment observation', () {
      const formatter = PrettyEventLogRecordFormatter();
      final record = eventRecord(
        phase: EventLogPhase.transition,
        duration: null,
        transitionIndex: 1,
        previousStateLabel: 'count:0',
        nextStateLabel: 'count:1',
        stateMetadata: const <String, Object?>{'changedBy': 1},
        metadata: const <String, Object?>{'amount': 1},
      );

      final entry = formatter.format(record);

      expect(entry.level, BlocpodLogLevel.info);
      expect(entry.message, contains('✨ state.transition -- CounterController'));
      expect(entry.message, contains('Event: IncrementEvent'));
      expect(entry.message, contains('previous: loading(count:0)'));
      expect(entry.message, contains('next: data(count:1)'));
      expect(entry.message, contains('transitionIndex: 1'));
      expect(entry.message, contains('hasChanged: true'));
      expect(entry.message, contains('eventMetadataKeys: amount'));
      expect(entry.message, contains('stateMetadataKeys: changedBy'));
      expect(entry.message, isNot(contains('amount=1')));
      expect(entry.message, isNot(contains('changedBy=1')));
      expect(entry.message, isNot(contains('onChange')));
      expect(entry.metadata, containsPair('phase', 'state.transition'));
      expect(entry.metadata, containsPair('hasChanged', true));
    });

    test('pretty formatter does not embed metadata values in messages', () {
      const formatter = PrettyEventLogRecordFormatter();
      final record = eventRecord(
        phase: EventLogPhase.transition,
        duration: null,
        transitionIndex: 1,
        previousStateLabel: 'ready',
        nextStateLabel: 'saving',
        metadata: const <String, Object?>{
          'customerEmail': 'user@example.com',
          'emailLength': 16,
          'token': 'abc',
          'secretKey': 'hidden',
          'credentialId': 'cred',
          'password': 'pw',
          'nested': <String, Object?>{'safe': 'visible', 'token': 'nested-token'},
        },
        stateMetadata: const <String, Object?>{'status': 'saving', 'password': 'state-password'},
      );

      final message = formatter.format(record).message;

      expect(message, contains('eventMetadataKeys: customerEmail,emailLength,nested'));
      expect(message, contains('stateMetadataKeys: status'));
      expect(message, isNot(contains('user@example.com')));
      expect(message, isNot(contains('emailLength=16')));
      expect(message, isNot(contains('nested={safe: visible}')));
      expect(message, isNot(contains('status=saving')));
      expect(message, isNot(contains('abc')));
      expect(message, isNot(contains('hidden')));
      expect(message, isNot(contains('cred')));
      expect(message, isNot(contains('pw')));
      expect(message, isNot(contains('nested-token')));
      expect(message, isNot(contains('state-password')));
    });

    test('pretty formatter preserves structured metadata for sinks', () {
      const formatter = PrettyEventLogRecordFormatter();
      final record = eventRecord(
        phase: EventLogPhase.transition,
        duration: null,
        transitionIndex: 1,
        metadata: const <String, Object?>{'token': 'sink-redaction-stays-with-sink'},
      );

      final entry = formatter.format(record);

      expect(entry.metadata, containsPair('token', 'sink-redaction-stays-with-sink'));
      expect(entry.message, isNot(contains('sink-redaction-stays-with-sink')));
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

final class StubEventLogFormatter implements BlocpodEventLogFormatter {
  const StubEventLogFormatter();

  @override
  BlocpodLogEntry format(EventLogRecord record) {
    return BlocpodLogEntry(
      level: BlocpodLogLevel.info,
      message: 'stub formatted',
      timestamp: record.startedAt,
      metadata: const <String, Object?>{'formatter': 'stub'},
    );
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
