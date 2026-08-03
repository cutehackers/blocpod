import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter_test/flutter_test.dart';

final class ThrowingText {
  @override
  String toString() => throw StateError('cannot stringify');
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
