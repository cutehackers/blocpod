import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BlocpodLogEntry preserves structured fields', () {
    final error = StateError('failed');
    final stackTrace = StackTrace.current;
    final timestamp = DateTime.utc(2026, 6);

    final entry = BlocpodLogEntry(
      level: BlocpodLogLevel.warning,
      message: 'dispatch finished',
      timestamp: timestamp,
      metadata: const {'traceId': 'trace-1'},
      error: error,
      stackTrace: stackTrace,
    );

    expect(entry.level, BlocpodLogLevel.warning);
    expect(entry.message, 'dispatch finished');
    expect(entry.timestamp, timestamp);
    expect(entry.metadata, containsPair('traceId', 'trace-1'));
    expect(entry.error, same(error));
    expect(entry.stackTrace, same(stackTrace));
  });

  test('DebugPrintLogSink formats local development output', () {
    final messages = <String>[];
    final sink = DebugPrintLogSink(
      debugPrintOverride: (message, {wrapWidth}) {
        messages.add(message ?? '');
      },
    );

    sink.write(
      BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: 'CounterController IncrementEvent data->data',
        timestamp: DateTime.utc(2026, 6, 1, 9, 30),
        metadata: const {'traceId': 'trace-1', 'durationMicros': 1200},
      ),
    );

    expect(messages, hasLength(1));
    expect(messages.single, contains('[info]'));
    expect(messages.single, contains('2026-06-01T09:30:00.000Z'));
    expect(messages.single, contains('CounterController IncrementEvent data->data'));
    expect(messages.single, contains('traceId=trace-1'));
    expect(messages.single, contains('durationMicros=1200'));
  });

  test('formatting does not print sensitive metadata by default', () {
    final formatted = formatBlocpodLogEntry(
      BlocpodLogEntry(
        level: BlocpodLogLevel.error,
        message: 'failed',
        timestamp: DateTime.utc(2026, 6),
        metadata: const {
          'token': 'abc',
          'secretKey': 'hidden',
          'credentialId': 'cred',
          'password': 'pw',
          'traceId': 'trace-1',
        },
      ),
    );

    expect(formatted, contains('traceId=trace-1'));
    expect(formatted, isNot(contains('abc')));
    expect(formatted, isNot(contains('hidden')));
    expect(formatted, isNot(contains('cred')));
    expect(formatted, isNot(contains('pw')));
  });

  test('formatting redacts nested sensitive metadata', () {
    final formatted = formatBlocpodLogEntry(
      BlocpodLogEntry(
        level: BlocpodLogLevel.error,
        message: 'failed',
        timestamp: DateTime.utc(2026, 6),
        metadata: const {
          'auth': {'userId': 'user-1', 'password': 'pw', 'token': 'abc'},
          'attempts': [
            {'step': 'refresh', 'secretKey': 'hidden', 'credentialId': 'cred'},
          ],
        },
      ),
    );

    expect(formatted, contains('auth={userId: user-1}'));
    expect(formatted, contains('attempts=[{step: refresh}]'));
    expect(formatted, isNot(contains('password')));
    expect(formatted, isNot(contains('token')));
    expect(formatted, isNot(contains('secretKey')));
    expect(formatted, isNot(contains('credentialId')));
    expect(formatted, isNot(contains('pw')));
    expect(formatted, isNot(contains('abc')));
    expect(formatted, isNot(contains('hidden')));
    expect(formatted, isNot(contains('cred')));
  });

  test('formatting includes stack traces for error entries', () {
    final formatted = formatBlocpodLogEntry(
      BlocpodLogEntry(
        level: BlocpodLogLevel.error,
        message: 'failed',
        timestamp: DateTime.utc(2026, 6),
        error: StateError('boom'),
        stackTrace: StackTrace.fromString('line 1\nline 2'),
      ),
    );

    expect(formatted, contains('error=Bad state: boom'));
    expect(formatted, contains('stackTrace=line 1'));
    expect(formatted, contains('line 2'));
  });
}
