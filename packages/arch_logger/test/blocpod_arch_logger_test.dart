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
      expect(sink.entries.single.attributes, containsPair('formatter', 'stub'));
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
      expect(entry.timestamp, record.occurredAt);
      expect(entry.sequence, record.recordSequence);
      expect(entry.traceId, record.traceContext.traceId);
      expect(entry.spanId, record.traceContext.spanId);
      expect(entry.parentSpanId, record.traceContext.parentSpanId);
      expect(entry.attributes, <String, Object?>{
        'phase': 'event.completed',
        'controllerName': 'CounterController',
        'eventName': 'IncrementEvent',
        'durationMicros': 12000,
        'previousStateKind': 'loading',
        'nextStateKind': 'data',
        'hasChanged': true,
        'eventMetadata': <String, Object?>{'feature': 'counter'},
      });
      expect(entry.error, isNull);
      expect(entry.stackTrace, isNull);
    });

    test('uses occurredAt as the log entry timestamp', () {
      final startedAt = DateTime.utc(2026, 7, 31, 9);
      final occurredAt = startedAt.add(const Duration(milliseconds: 25));
      final record = EventLogRecord(
        phase: EventLogPhase.eventCompleted,
        traceContext: TraceContext.root(startedAt: startedAt),
        controllerName: 'CounterController',
        eventName: 'IncrementEvent',
        startedAt: startedAt,
        occurredAt: occurredAt,
      );

      final entry = const EventLogRecordFormatter().format(record);

      expect(entry.timestamp, occurredAt);
      expect(entry.timestamp, isNot(startedAt));
    });

    test('maps a non-null recordSequence to the dedicated sequence field', () {
      final startedAt = DateTime.utc(2026, 7, 31, 9);
      final record = EventLogRecord(
        phase: EventLogPhase.eventCompleted,
        traceContext: TraceContext.root(startedAt: startedAt),
        controllerName: 'CounterController',
        startedAt: startedAt,
        recordSequence: 42,
      );

      final entry = const EventLogRecordFormatter().format(record);

      expect(entry.sequence, 42);
    });

    test('omits sequence when recordSequence is null', () {
      final entry = const EventLogRecordFormatter().format(eventRecord());

      expect(entry.sequence, isNull);
    });

    test('caller metadata cannot override dedicated fields and stays nested', () {
      final startedAt = DateTime.utc(2026, 7, 31, 9);
      final traceContext = TraceContext.root(startedAt: startedAt);
      final record = EventLogRecord(
        phase: EventLogPhase.eventCompleted,
        traceContext: traceContext.child(startedAt: startedAt.add(const Duration(milliseconds: 1))),
        controllerName: 'CounterController',
        eventName: 'IncrementEvent',
        startedAt: startedAt,
        occurredAt: startedAt.add(const Duration(milliseconds: 12)),
        recordSequence: 42,
        duration: const Duration(milliseconds: 12),
        previousStateKind: AsyncValueKind.loading,
        nextStateKind: AsyncValueKind.data,
        hasChanged: true,
        metadata: const <String, Object?>{
          'phase': 'wrong-phase',
          'sequence': -1,
          'traceId': 'wrong-trace',
          'feature': 'counter',
        },
        stateMetadata: const <String, Object?>{'status': 'busy'},
      );

      final entry = const EventLogRecordFormatter().format(record);

      expect(entry.sequence, 42);
      expect(entry.traceId, record.traceContext.traceId);
      expect(entry.spanId, record.traceContext.spanId);
      expect(entry.parentSpanId, record.traceContext.parentSpanId);
      expect(entry.attributes['phase'], 'event.completed');
      expect(entry.attributes['eventMetadata'], <String, Object?>{
        'phase': 'wrong-phase',
        'sequence': -1,
        'traceId': 'wrong-trace',
        'feature': 'counter',
      });
      expect(entry.attributes['stateMetadata'], <String, Object?>{'status': 'busy'});
    });

    test('preserves caller collision keys inside event metadata', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final record = eventRecord(
        transitionIndex: 2,
        previousStateLabel: 'ready',
        nextStateLabel: 'saving',
        stateMetadata: const <String, Object?>{'status': 'busy'},
        metadata: const <String, Object?>{
          'phase': 'wrong-phase',
          'sequence': -1,
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

      final entry = sink.entries.single;
      expect(entry.sequence, isNull);
      expect(entry.traceId, record.traceContext.traceId);
      expect(entry.spanId, record.traceContext.spanId);
      expect(entry.parentSpanId, record.traceContext.parentSpanId);
      expect(entry.attributes['phase'], 'event.completed');
      expect(entry.attributes['controllerName'], 'CounterController');
      expect(entry.attributes['eventName'], 'IncrementEvent');
      expect(entry.attributes['durationMicros'], 12000);
      expect(entry.attributes['transitionIndex'], 2);
      expect(entry.attributes['previousStateKind'], 'loading');
      expect(entry.attributes['nextStateKind'], 'data');
      expect(entry.attributes['hasChanged'], true);
      expect(entry.attributes['previousStateLabel'], 'ready');
      expect(entry.attributes['nextStateLabel'], 'saving');
      expect(entry.attributes['eventMetadata'], <String, Object?>{
        'phase': 'wrong-phase',
        'sequence': -1,
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
      });
      expect(entry.attributes['stateMetadata'], <String, Object?>{'status': 'busy'});
    });

    test('drops fake parent span metadata for root spans', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final record = eventRecord(
        useRootTraceContext: true,
        metadata: const <String, Object?>{'parentSpanId': 'fake', 'feature': 'counter'},
      );

      logger.log(record);

      final entry = sink.entries.single;
      expect(record.traceContext.parentSpanId, isNull);
      expect(entry.parentSpanId, isNull);
      expect(entry.attributes['eventMetadata'], <String, Object?>{
        'parentSpanId': 'fake',
        'feature': 'counter',
      });
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
      expect(entry.attributes, containsPair('phase', 'state.transition'));
      expect(entry.attributes, containsPair('transitionIndex', 2));
      expect(entry.attributes, containsPair('previousStateLabel', 'ready'));
      expect(entry.attributes, containsPair('nextStateLabel', 'saving'));
      expect(entry.attributes, containsPair('stateMetadata', <String, Object?>{'status': 'busy'}));
      expect(entry.attributes.containsKey('durationMicros'), isFalse);
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
      final attributes = sink.entries.single.attributes;
      expect(attributes, containsPair('hasChanged', true));
      expect(attributes, containsPair('phase', 'state.transition'));
      expect(attributes, containsPair('previousStateLabel', 'count:0'));
      expect(attributes, containsPair('nextStateLabel', 'count:1'));
      expect(attributes, containsPair('stateMetadata', <String, Object?>{'changedBy': 1}));
    });

    test('event phase labels are optimized for log scanning', () {
      expect(eventLogPhaseLabel(EventLogPhase.controllerCreated), 'controller.created');
      expect(eventLogPhaseLabel(EventLogPhase.initialStateEstablished), 'state.established');
      expect(eventLogPhaseLabel(EventLogPhase.eventStarted), 'event.started');
      expect(eventLogPhaseLabel(EventLogPhase.transition), 'state.transition');
      expect(eventLogPhaseLabel(EventLogPhase.eventCompleted), 'event.completed');
      expect(eventLogPhaseLabel(EventLogPhase.eventFailed), 'event.failed');
      expect(eventLogPhaseLabel(EventLogPhase.controllerDisposed), 'controller.disposed');
    });

    test('compact formatter maps initialized state without transition or event fields', () {
      const formatter = EventLogRecordFormatter();

      final entry = formatter.format(establishedInitialStateRecord());

      expect(entry.message, 'CounterController state.established ->data');
      expect(entry.attributes, containsPair('phase', 'state.established'));
      expect(entry.attributes, containsPair('controllerName', 'CounterController'));
      expect(entry.attributes, containsPair('nextStateKind', 'data'));
      expect(entry.attributes, containsPair('nextStateLabel', 'ready'));
      expect(entry.attributes, containsPair('stateMetadata', <String, Object?>{'status': 'ready'}));
      expect(entry.attributes, containsPair('eventMetadata', <String, Object?>{'feature': 'counter'}));
      expect(entry.attributes.containsKey('eventName'), isFalse);
      expect(entry.attributes.containsKey('previousStateKind'), isFalse);
      expect(entry.attributes.containsKey('previousStateLabel'), isFalse);
      expect(entry.attributes.containsKey('hasChanged'), isFalse);
    });

    test('pretty formatter renders the exact one-line message for every event phase', () {
      const formatter = PrettyEventLogRecordFormatter();
      const expectedMessages = <EventLogPhase, String>{
        EventLogPhase.controllerCreated: '🟢 CounterController created',
        EventLogPhase.initialStateEstablished: '🔵 CounterController established data(ready)',
        EventLogPhase.eventStarted:
            '🟡 CounterController · IncrementEvent started from loading(count:0)',
        EventLogPhase.transition:
            '✨ CounterController · IncrementEvent transition[1] loading(count:0) → data(count:1)',
        EventLogPhase.eventCompleted:
            '✅ CounterController · IncrementEvent completed loading(count:0) → data(count:1) in 12ms',
        EventLogPhase.eventFailed:
            '🔴 CounterController · IncrementEvent failed loading(count:0) → data(count:1) in 12ms',
        EventLogPhase.controllerDisposed: '⚪ CounterController disposed',
      };

      for (final entry in expectedMessages.entries) {
        final result = formatter.format(prettyRecordFor(entry.key));
        expect(
          result.level,
          entry.key == EventLogPhase.eventFailed ? BlocpodLogLevel.error : BlocpodLogLevel.info,
          reason: 'phase ${entry.key}',
        );
        expect(result.message, entry.value, reason: 'phase ${entry.key}');
        expect(result.message.contains('\n'), isFalse, reason: 'phase ${entry.key}');
        expect(result.message.contains('\r'), isFalse, reason: 'phase ${entry.key}');
      }
    });

    test('pretty formatter formats durations at the exact unit boundaries', () {
      const formatter = PrettyEventLogRecordFormatter();
      final expectedDurations = <({Duration duration, String text})>[
        (duration: const Duration(microseconds: 840), text: '840µs'),
        (duration: const Duration(microseconds: 1000), text: '1ms'),
        (duration: const Duration(milliseconds: 124), text: '124ms'),
        (duration: const Duration(milliseconds: 999), text: '999ms'),
        (duration: const Duration(seconds: 1), text: '1s'),
        (duration: const Duration(milliseconds: 1240), text: '1.24s'),
        (duration: const Duration(milliseconds: 2000), text: '2s'),
      ];

      for (final entry in expectedDurations) {
        final result = formatter.format(
          prettyCompletedRecordWithDuration(entry.duration),
        );
        expect(result.message, endsWith('in ${entry.text}'), reason: 'duration ${entry.duration}');
        expect(result.message.contains('\n'), isFalse, reason: 'duration ${entry.duration}');
        expect(result.message.contains('\r'), isFalse, reason: 'duration ${entry.duration}');
      }
    });

    test('pretty formatter omits the duration suffix when completed or failed records have no duration', () {
      const formatter = PrettyEventLogRecordFormatter();
      final completed = EventLogRecord(
        phase: EventLogPhase.eventCompleted,
        traceContext: TraceContext.root(startedAt: DateTime.utc(2026, 8, 3, 10)),
        controllerName: 'CounterController',
        eventName: 'IncrementEvent',
        startedAt: DateTime.utc(2026, 8, 3, 10),
        previousStateKind: AsyncValueKind.loading,
        previousStateLabel: 'count:0',
        nextStateKind: AsyncValueKind.data,
        nextStateLabel: 'count:1',
      );
      final failed = EventLogRecord(
        phase: EventLogPhase.eventFailed,
        traceContext: TraceContext.root(startedAt: DateTime.utc(2026, 8, 3, 10)),
        controllerName: 'CounterController',
        eventName: 'IncrementEvent',
        startedAt: DateTime.utc(2026, 8, 3, 10),
        previousStateKind: AsyncValueKind.loading,
        previousStateLabel: 'count:0',
        nextStateKind: AsyncValueKind.data,
        nextStateLabel: 'count:1',
        error: StateError('failed'),
      );

      expect(
        formatter.format(completed).message,
        '✅ CounterController · IncrementEvent completed loading(count:0) → data(count:1)',
      );
      expect(
        formatter.format(failed).message,
        '🔴 CounterController · IncrementEvent failed loading(count:0) → data(count:1)',
      );
      expect(formatter.format(completed).message, isNot(contains('in unknown')));
      expect(formatter.format(failed).message, isNot(contains('in unknown')));
    });

    test('pretty formatter preserves dedicated fields and attributes while replacing only message', () {
      final startedAt = DateTime.utc(2026, 7, 31, 9);
      final record = EventLogRecord(
        phase: EventLogPhase.transition,
        traceContext: TraceContext.root(startedAt: startedAt),
        controllerName: 'CounterController',
        eventName: 'IncrementEvent',
        startedAt: startedAt,
        recordSequence: 42,
        metadata: const <String, Object?>{'recordSequence': -1, 'feature': 'counter'},
      );

      final entry = const PrettyEventLogRecordFormatter().format(record);
      final compact = const EventLogRecordFormatter().format(record);

      expect(entry.level, compact.level);
      expect(entry.timestamp, compact.timestamp);
      expect(entry.sequence, compact.sequence);
      expect(entry.traceId, compact.traceId);
      expect(entry.spanId, compact.spanId);
      expect(entry.parentSpanId, compact.parentSpanId);
      expect(entry.attributes, compact.attributes);
      expect(entry.error, compact.error);
      expect(entry.stackTrace, compact.stackTrace);
      expect(entry.message, '✨ CounterController · IncrementEvent transition[0] unknown → unknown');
    });

    test('pretty formatter uses unknown fallbacks only when event data is missing', () {
      const formatter = PrettyEventLogRecordFormatter();
      final startedFallback = EventLogRecord(
        phase: EventLogPhase.eventStarted,
        traceContext: TraceContext.root(startedAt: DateTime.utc(2026, 8, 3, 10)),
        controllerName: 'CounterController',
        startedAt: DateTime.utc(2026, 8, 3, 10),
      );
      final establishedFallback = EventLogRecord(
        phase: EventLogPhase.initialStateEstablished,
        traceContext: TraceContext.root(startedAt: DateTime.utc(2026, 8, 3, 10)),
        controllerName: 'CounterController',
        startedAt: DateTime.utc(2026, 8, 3, 10),
      );

      expect(
        formatter.format(startedFallback).message,
        '🟡 CounterController · unknownEvent started from unknown',
      );
      expect(
        formatter.format(establishedFallback).message,
        '🔵 CounterController established unknown',
      );
    });

    test('pretty formatter keeps metadata structured for sinks without appending summaries to the message', () {
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

      expect(message, '✨ CounterController · IncrementEvent transition[1] loading(ready) → data(saving)');
      expect(message, isNot(contains('user@example.com')));
      expect(message, isNot(contains('status=saving')));
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

      expect(
        entry.attributes,
        containsPair('eventMetadata', <String, Object?>{'token': 'sink-redaction-stays-with-sink'}),
      );
      expect(entry.message, '✨ CounterController · IncrementEvent transition[1] loading → data');
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

    test('preserves attribute insertion order and raw sink identity', () {
      final record = eventRecord(
        phase: EventLogPhase.transition,
        duration: const Duration(milliseconds: 12),
        transitionIndex: 2,
        previousStateLabel: 'ready',
        nextStateLabel: 'saving',
        metadata: const <String, Object?>{'feature': 'counter'},
        stateMetadata: const <String, Object?>{'status': 'busy'},
      );

      final entry = const EventLogRecordFormatter().format(record);

      expect(entry.sequence, isNull);
      expect(entry.traceId, record.traceContext.traceId);
      expect(entry.attributes.keys, orderedEquals(<String>[
        'phase',
        'controllerName',
        'eventName',
        'durationMicros',
        'transitionIndex',
        'previousStateKind',
        'nextStateKind',
        'hasChanged',
        'previousStateLabel',
        'nextStateLabel',
        'eventMetadata',
        'stateMetadata',
      ]));

      final sink = MemoryLogSink()..write(entry);
      expect(sink.entries.single, same(entry));
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
      attributes: const <String, Object?>{'formatter': 'stub'},
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

EventLogRecord establishedInitialStateRecord({Object? error, StackTrace? stackTrace}) {
  final startedAt = DateTime.utc(2026, 7, 30, 9, 30);
  return EventLogRecord(
    phase: EventLogPhase.initialStateEstablished,
    traceContext: TraceContext.root(startedAt: startedAt),
    controllerName: 'CounterController',
    startedAt: startedAt,
    nextStateKind: error == null ? AsyncValueKind.data : AsyncValueKind.error,
    nextStateLabel: error == null ? 'ready' : 'error',
    stateMetadata: const <String, Object?>{'status': 'ready'},
    error: error,
    stackTrace: stackTrace,
    metadata: const <String, Object?>{'feature': 'counter'},
  );
}

EventLogRecord prettyRecordFor(EventLogPhase phase) {
  final startedAt = DateTime.utc(2026, 8, 3, 10);
  final isEvent = switch (phase) {
    EventLogPhase.eventStarted ||
    EventLogPhase.transition ||
    EventLogPhase.eventCompleted ||
    EventLogPhase.eventFailed => true,
    _ => false,
  };
  return EventLogRecord(
    phase: phase,
    traceContext: TraceContext.root(startedAt: startedAt),
    controllerName: 'CounterController',
    eventName: isEvent ? 'IncrementEvent' : null,
    startedAt: startedAt,
    duration:
        phase == EventLogPhase.eventCompleted || phase == EventLogPhase.eventFailed
            ? const Duration(milliseconds: 12)
            : null,
    transitionIndex: phase == EventLogPhase.transition ? 1 : null,
    previousStateKind: isEvent ? AsyncValueKind.loading : null,
    previousStateLabel: isEvent ? 'count:0' : null,
    nextStateKind: switch (phase) {
      EventLogPhase.initialStateEstablished ||
      EventLogPhase.transition ||
      EventLogPhase.eventCompleted ||
      EventLogPhase.eventFailed => AsyncValueKind.data,
      _ => null,
    },
    nextStateLabel: switch (phase) {
      EventLogPhase.initialStateEstablished => 'ready',
      EventLogPhase.transition || EventLogPhase.eventCompleted || EventLogPhase.eventFailed => 'count:1',
      _ => null,
    },
    error: phase == EventLogPhase.eventFailed ? StateError('failed') : null,
  );
}

EventLogRecord prettyCompletedRecordWithDuration(Duration duration) {
  final startedAt = DateTime.utc(2026, 8, 3, 10);
  return EventLogRecord(
    phase: EventLogPhase.eventCompleted,
    traceContext: TraceContext.root(startedAt: startedAt),
    controllerName: 'CounterController',
    eventName: 'IncrementEvent',
    startedAt: startedAt,
    duration: duration,
    previousStateKind: AsyncValueKind.loading,
    previousStateLabel: 'count:0',
    nextStateKind: AsyncValueKind.data,
    nextStateLabel: 'count:1',
  );
}
