import 'dart:collection';
import 'dart:convert';

import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter_test/flutter_test.dart';

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
  group('PrettyLogEncoder', () {
    final entry = BlocpodLogEntry(
      level: BlocpodLogLevel.info,
      message: '✨ CounterController · IncrementEvent transition[1] data(count:0) → data(count:1)',
      timestamp: DateTime.parse('2026-08-03T19:00:01.001+09:00'),
      sequence: 104,
      traceId: 'trace-ab12',
      spanId: 'span-cd34',
      parentSpanId: 'span-parent',
      attributes: const <String, Object?>{'phase': 'state.transition', 'transitionIndex': 1},
    );

    test('compact prints only time, level, and message', () {
      expect(
        const PrettyLogEncoder().encode(entry),
        '10:00:01.001Z INFO  ✨ CounterController · IncrementEvent transition[1] data(count:0) → data(count:1)',
      );
    });

    test('verbose appends only available diagnostics', () {
      expect(
        const PrettyLogEncoder(detail: PrettyLogDetail.verbose).encode(entry),
        '10:00:01.001Z INFO  ✨ CounterController · IncrementEvent transition[1] data(count:0) → data(count:1)\n'
        '  sequence=104 trace=trace-ab12/span-cd34 parent=span-parent\n'
        '  attributes={phase: state.transition, transitionIndex: 1}',
      );
    });

    test('compact renders error and stack trace on following lines', () {
      final output = const PrettyLogEncoder().encode(
        BlocpodLogEntry(
          level: BlocpodLogLevel.error,
          message: '🔴 Save failed',
          timestamp: DateTime.utc(2026, 8, 3, 10),
          error: StateError('save failed'),
          stackTrace: StackTrace.fromString('#0 save\n#1 dispatch'),
        ),
      );

      expect(
        output,
        '10:00:00.000Z ERROR 🔴 Save failed\n'
        '  StateError: Bad state: save failed\n'
        '  #0 save\n'
        '  #1 dispatch',
      );
    });

    test('verbose safely renders cycles and throwing objects', () {
      final cycle = <Object?>[];
      cycle.add(cycle);
      final output = const PrettyLogEncoder(detail: PrettyLogDetail.verbose).encode(
        BlocpodLogEntry(
          level: BlocpodLogLevel.info,
          message: 'safe values',
          timestamp: DateTime.utc(2026, 8, 3),
          attributes: <String, Object?>{'cycle': cycle, 'odd': ThrowingText()},
        ),
      );

      expect(output, contains('<cycle>'));
      expect(output, contains('<ThrowingText>'));
    });

    test('verbose preserves the base line when attributes cannot be inspected', () {
      final entry = BlocpodLogEntry(
        level: BlocpodLogLevel.warning,
        message: 'keep this event',
        timestamp: DateTime.utc(2026, 8, 3, 11, 12, 13, 14),
        attributes: ThrowingStringMap(),
      );

      expect(() => const PrettyLogEncoder(detail: PrettyLogDetail.verbose).encode(entry), returnsNormally);
      expect(
        const PrettyLogEncoder(detail: PrettyLogDetail.verbose).encode(entry),
        '11:12:13.014Z WARNING keep this event',
      );
    });

    test('verbose matches JSON attribute depth at the nested-container boundary', () {
      final entry = BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: 'depth',
        timestamp: DateTime.utc(2026, 8, 3),
        attributes: const <String, Object?>{
          'root': <String, Object?>{
            'd2': <String, Object?>{
              'd3': <String, Object?>{
                'd4': <String, Object?>{
                  'd5': <String, Object?>{
                    'd6': <String, Object?>{
                      'd7': <String, Object?>{
                        'd8': <String, Object?>{'leaf': 1},
                      },
                    },
                  },
                },
              },
            },
          },
        },
      );

      final jsonAttributes =
          (jsonDecode(const JsonLogEncoder(maxDepth: 8).encode(entry)) as Map<String, Object?>)['attributes'];

      expect(jsonAttributes, <String, Object?>{
        'root': <String, Object?>{
          'd2': <String, Object?>{
            'd3': <String, Object?>{
              'd4': <String, Object?>{
                'd5': <String, Object?>{
                  'd6': <String, Object?>{
                    'd7': <String, Object?>{'d8': '<max-depth-exceeded>'},
                  },
                },
              },
            },
          },
        },
      });
      expect(
        const PrettyLogEncoder(detail: PrettyLogDetail.verbose).encode(entry),
        '00:00:00.000Z INFO  depth\n'
        '  attributes={root: {d2: {d3: {d4: {d5: {d6: {d7: {d8: <max-depth-exceeded>}}}}}}}}',
      );
    });

    test('compact hides diagnostics and empty verbose adds no lines', () {
      final compact = const PrettyLogEncoder().encode(entry);
      expect(compact, isNot(contains('sequence=')));
      expect(compact, isNot(contains('trace=')));
      expect(compact, isNot(contains('attributes=')));

      final plain = BlocpodLogEntry(level: BlocpodLogLevel.info, message: 'plain', timestamp: DateTime.utc(2026, 8, 3));
      expect(
        const PrettyLogEncoder(detail: PrettyLogDetail.verbose).encode(plain),
        const PrettyLogEncoder().encode(plain),
      );
    });
  });
}
