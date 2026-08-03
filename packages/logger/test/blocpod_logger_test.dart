import 'dart:convert';

import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter_test/flutter_test.dart';

final class RecordingSink implements BlocpodLogSink {
  final List<BlocpodLogEntry> entries = <BlocpodLogEntry>[];

  @override
  void write(BlocpodLogEntry entry) => entries.add(entry);
}

void main() {
  test('BlocpodLogEntry preserves transport-neutral structured fields', () {
    final error = StateError('failed');
    final stackTrace = StackTrace.current;
    final timestamp = DateTime.utc(2026, 8, 3);

    final entry = BlocpodLogEntry(
      level: BlocpodLogLevel.warning,
      message: 'dispatch finished',
      timestamp: timestamp,
      sequence: 41,
      traceId: 'trace-1',
      spanId: 'span-1',
      parentSpanId: 'span-0',
      attributes: const <String, Object?>{'phase': 'event.completed'},
      error: error,
      stackTrace: stackTrace,
    );

    expect(entry.level, BlocpodLogLevel.warning);
    expect(entry.message, 'dispatch finished');
    expect(entry.timestamp, timestamp);
    expect(entry.sequence, 41);
    expect(entry.traceId, 'trace-1');
    expect(entry.spanId, 'span-1');
    expect(entry.parentSpanId, 'span-0');
    expect(entry.attributes, containsPair('phase', 'event.completed'));
    expect(entry.error, same(error));
    expect(entry.stackTrace, same(stackTrace));
  });

  test('user-provided sink receives the original structured entry', () {
    final sink = RecordingSink();
    final entry = BlocpodLogEntry(
      level: BlocpodLogLevel.info,
      message: 'direct',
      timestamp: DateTime.utc(2026, 8, 3),
      sequence: 7,
      attributes: const <String, Object?>{'feature': 'counter'},
    );

    sink.write(entry);

    expect(sink.entries.single, same(entry));
    expect(sink.entries.single.sequence, 7);
  });

  test('DebugPrintLogSink uses JSON Lines by default in one callback', () {
    final messages = <String>[];
    final sink = DebugPrintLogSink(
      debugPrintOverride: (message, {wrapWidth}) {
        messages.add(message ?? '');
      },
    );

    sink.write(
      BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: 'created',
        timestamp: DateTime.utc(2026, 8, 3),
      ),
    );

    expect(messages, hasLength(1));
    expect(jsonDecode(messages.single), containsPair('schema', 'blocpod.log'));
  });

  test('DebugPrintLogSink uses the injected encoder', () {
    final messages = <String>[];
    final sink = DebugPrintLogSink(
      encoder: const PrefixEncoder(),
      debugPrintOverride: (String? message, {int? wrapWidth}) {
        messages.add(message ?? '');
      },
    );

    sink.write(
      BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: 'created',
        timestamp: DateTime.utc(2026, 8, 3),
      ),
    );

    expect(messages, <String>['encoded:created']);
  });

  test('formatBlocpodLogEntry delegates to the default JSON encoder', () {
    final entry = BlocpodLogEntry(
      level: BlocpodLogLevel.info,
      message: 'created',
      timestamp: DateTime.utc(2026, 8, 3),
    );

    expect(formatBlocpodLogEntry(entry), const JsonLogEncoder().encode(entry));
  });
}

final class PrefixEncoder implements BlocpodLogEncoder {
  const PrefixEncoder();

  @override
  String encode(BlocpodLogEntry entry) => 'encoded:${entry.message}';
}
