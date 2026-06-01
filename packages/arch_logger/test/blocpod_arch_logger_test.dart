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
      expect(entry.message, 'CounterController IncrementEvent loading->data 12ms');
      expect(entry.timestamp, record.startedAt);
      expect(entry.metadata, <String, Object?>{
        'traceId': record.traceContext.traceId,
        'spanId': record.traceContext.spanId,
        'parentSpanId': record.traceContext.parentSpanId,
        'controllerName': 'CounterController',
        'eventName': 'IncrementEvent',
        'durationMicros': 12000,
        'beforeStateKind': 'loading',
        'afterStateKind': 'data',
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
        metadata: const <String, Object?>{
          'traceId': 'wrong-trace',
          'controllerName': 'WrongController',
          'durationMicros': -1,
          'feature': 'counter',
        },
      );

      logger.log(record);

      final metadata = sink.entries.single.metadata;
      expect(metadata['traceId'], record.traceContext.traceId);
      expect(metadata['controllerName'], 'CounterController');
      expect(metadata['durationMicros'], 12000);
      expect(metadata['feature'], 'counter');
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
  Object? error,
  StackTrace? stackTrace,
  Map<String, Object?> metadata = const <String, Object?>{'feature': 'counter'},
}) {
  final startedAt = DateTime.utc(2026, 6, 1, 9, 30);
  final traceContext = TraceContext.root(
    startedAt: startedAt.subtract(const Duration(milliseconds: 1)),
  ).child(startedAt: startedAt);

  return EventLogRecord(
    traceContext: traceContext,
    controllerName: 'CounterController',
    eventName: 'IncrementEvent',
    startedAt: startedAt,
    duration: const Duration(milliseconds: 12),
    beforeStateKind: AsyncValueKind.loading,
    afterStateKind: AsyncValueKind.data,
    hasChanged: true,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
  );
}
