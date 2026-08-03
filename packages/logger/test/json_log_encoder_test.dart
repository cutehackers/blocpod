import 'dart:collection';
import 'dart:convert';

import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter_test/flutter_test.dart';

enum ExamplePhase { started }

final class ThrowingText {
  @override
  String toString() => throw StateError('cannot stringify');
}

final class ThrowingStringMap extends MapBase<String, Object?> {
  @override
  Object? operator [](Object? key) => null;

  @override
  void operator []=(String key, Object? value) {}

  @override
  void clear() {}

  @override
  Iterable<String> get keys => throw StateError('cannot iterate');

  @override
  Object? remove(Object? key) => null;
}

void main() {
  group('JsonLogEncoder', () {
    const encoder = JsonLogEncoder();

    test('emits a deterministic one-line versioned envelope', () {
      final encoded = encoder.encode(
        BlocpodLogEntry(
          level: BlocpodLogLevel.info,
          message: 'Counter transition\nquoted "value"',
          timestamp: DateTime.parse('2026-08-03T10:00:01.001+09:00'),
          sequence: 104,
          traceId: 'trace-ab12',
          spanId: 'span-cd34',
          parentSpanId: 'span-parent',
          attributes: const <String, Object?>{'phase': 'state.transition', 'hasChanged': true},
        ),
      );

      expect(encoded.contains('\n'), isFalse);
      expect(
        encoded,
        '{"schema":"blocpod.log","schemaVersion":1,"timestamp":"2026-08-03T01:00:01.001Z",'
        '"sequence":104,"level":"info","message":"Counter transition\\nquoted \\"value\\"",'
        '"trace":{"traceId":"trace-ab12","spanId":"span-cd34","parentSpanId":"span-parent"},'
        '"attributes":{"phase":"state.transition","hasChanged":true}}',
      );
      expect(jsonDecode(encoded), isA<Map<String, Object?>>());
    });

    test('omits absent optional sections and null trace members', () {
      final withoutOptional = encoder.encode(
        BlocpodLogEntry(level: BlocpodLogLevel.debug, message: 'created', timestamp: DateTime.utc(2026, 8, 3)),
      );
      final partialTrace =
          jsonDecode(
                encoder.encode(
                  BlocpodLogEntry(
                    level: BlocpodLogLevel.info,
                    message: 'partial trace',
                    timestamp: DateTime.utc(2026, 8, 3),
                    spanId: 'span-only',
                  ),
                ),
              )
              as Map<String, Object?>;

      expect(jsonDecode(withoutOptional), <String, Object?>{
        'schema': 'blocpod.log',
        'schemaVersion': 1,
        'timestamp': '2026-08-03T00:00:00.000Z',
        'level': 'debug',
        'message': 'created',
      });
      expect(partialTrace['trace'], <String, Object?>{'spanId': 'span-only'});
    });

    test('round-trips quotes, backslashes, and line breaks through JSON escaping', () {
      const message = 'quoted "value" at C:\\temp\nnext line';
      final encoded = encoder.encode(
        BlocpodLogEntry(level: BlocpodLogLevel.info, message: message, timestamp: DateTime.utc(2026, 8, 3)),
      );

      expect(encoded.contains('\n'), isFalse);
      expect((jsonDecode(encoded) as Map<String, Object?>)['message'], message);
    });

    test('rejects non-positive maxDepth in checked builds', () {
      expect(() => JsonLogEncoder(maxDepth: 0), throwsAssertionError);
    });

    test('normalizes Dart values without redaction', () {
      final decoded =
          jsonDecode(
                const JsonLogEncoder().encode(
                  BlocpodLogEntry(
                    level: BlocpodLogLevel.info,
                    message: 'values',
                    timestamp: DateTime.utc(2026, 8, 3),
                    attributes: <String, Object?>{
                      'when': DateTime.parse('2026-08-03T09:00:00+09:00'),
                      'elapsed': const Duration(microseconds: 1250),
                      'phaseEnum': ExamplePhase.started,
                      'numbers': <Object?>[1, 1.5, double.nan, double.infinity, double.negativeInfinity],
                      'password': 'kept-by-contract',
                      'odd': ThrowingText(),
                      'oddKeys': <Object?, Object?>{1: 'numeric-key', '1': 'string-key-wins'},
                    },
                  ),
                ),
              )
              as Map<String, Object?>;
      final attributes = decoded['attributes'] as Map<String, Object?>;

      expect(attributes['when'], '2026-08-03T00:00:00.000Z');
      expect(attributes['elapsed'], 1250);
      expect(attributes['phaseEnum'], 'started');
      expect(attributes['numbers'], <Object?>[1, 1.5, 'NaN', 'Infinity', '-Infinity']);
      expect(attributes['password'], 'kept-by-contract');
      expect(attributes['odd'], '<ThrowingText>');
      expect(attributes['oddKeys'], <String, Object?>{'1': 'string-key-wins'});
    });

    test('normalizes null map keys and lets a later string key win', () {
      final decoded =
          jsonDecode(
                const JsonLogEncoder().encode(
                  BlocpodLogEntry(
                    level: BlocpodLogLevel.info,
                    message: 'null key',
                    timestamp: DateTime.utc(2026, 8, 3),
                    attributes: <String, Object?>{
                      'keys': <Object?, Object?>{null: 'from-null-key', 'null': 'from-string-key'},
                    },
                  ),
                ),
              )
              as Map<String, Object?>;

      expect(decoded['attributes'], <String, Object?>{
        'keys': <String, Object?>{'null': 'from-string-key'},
      });
    });

    test('marks active-path cycles but preserves shared sibling values', () {
      final cycle = <Object?>[];
      cycle.add(cycle);
      final mapCycle = <String, Object?>{};
      mapCycle['self'] = mapCycle;
      final shared = <String, Object?>{'value': 1};
      final decoded =
          jsonDecode(
                const JsonLogEncoder().encode(
                  BlocpodLogEntry(
                    level: BlocpodLogLevel.info,
                    message: 'graph',
                    timestamp: DateTime.utc(2026, 8, 3),
                    attributes: <String, Object?>{
                      'iterableCycle': cycle,
                      'mapCycle': mapCycle,
                      'left': shared,
                      'right': shared,
                    },
                  ),
                ),
              )
              as Map<String, Object?>;
      final attributes = decoded['attributes'] as Map<String, Object?>;

      expect(attributes['iterableCycle'], <Object?>['<cycle>']);
      expect(attributes['mapCycle'], <String, Object?>{'self': '<cycle>'});
      expect(attributes['left'], <String, Object?>{'value': 1});
      expect(attributes['right'], <String, Object?>{'value': 1});
    });

    test('marks values beyond maxDepth', () {
      final decoded =
          jsonDecode(
                const JsonLogEncoder(maxDepth: 2).encode(
                  BlocpodLogEntry(
                    level: BlocpodLogLevel.info,
                    message: 'depth',
                    timestamp: DateTime.utc(2026, 8, 3),
                    attributes: const <String, Object?>{
                      'root': <String, Object?>{
                        'child': <String, Object?>{'leaf': 1},
                      },
                    },
                  ),
                ),
              )
              as Map<String, Object?>;

      expect((decoded['attributes'] as Map<String, Object?>)['root'], <String, Object?>{
        'child': '<max-depth-exceeded>',
      });
    });

    test('encodes errors and stack traces as a structured object', () {
      final decoded =
          jsonDecode(
                const JsonLogEncoder().encode(
                  BlocpodLogEntry(
                    level: BlocpodLogLevel.error,
                    message: 'failed',
                    timestamp: DateTime.utc(2026, 8, 3),
                    error: StateError('boom'),
                    stackTrace: StackTrace.fromString('#0 save\n#1 dispatch'),
                  ),
                ),
              )
              as Map<String, Object?>;

      expect(decoded['error'], <String, Object?>{
        'type': 'StateError',
        'message': 'Bad state: boom',
        'stackTrace': '#0 save\n#1 dispatch',
      });
    });

    test('stack-trace-only errors omit type and message', () {
      final decoded =
          jsonDecode(
                const JsonLogEncoder().encode(
                  BlocpodLogEntry(
                    level: BlocpodLogLevel.error,
                    message: 'failed',
                    timestamp: DateTime.utc(2026, 8, 3),
                    stackTrace: StackTrace.fromString('#0 dispatch'),
                  ),
                ),
              )
              as Map<String, Object?>;

      expect(decoded['error'], <String, Object?>{'stackTrace': '#0 dispatch'});
    });

    test('returns minimal valid JSON when normalization fails completely', () {
      final result = const JsonLogEncoder().encode(
        BlocpodLogEntry(
          level: BlocpodLogLevel.info,
          message: 'unencodable',
          timestamp: DateTime.utc(2026, 8, 3),
          attributes: ThrowingStringMap(),
        ),
      );

      expect(result.contains('\n'), isFalse);
      expect(jsonDecode(result), <String, Object?>{
        'schema': 'blocpod.log',
        'schemaVersion': 1,
        'timestamp': '2026-08-03T00:00:00.000Z',
        'level': 'error',
        'message': 'Blocpod log encoding failed',
      });
    });
  });
}
