import 'dart:async';
import 'dart:math';

const _traceContextZoneKey = Object();

/// Trace identity for a dispatched event span.
final class TraceContext {
  const TraceContext._({
    required this.traceId,
    required this.spanId,
    required this.parentSpanId,
    required this.startedAt,
  });

  /// Identifier shared by all spans in one dispatch tree.
  final String traceId;

  /// Identifier for this event dispatch span.
  final String spanId;

  /// Parent span identifier for nested dispatches.
  final String? parentSpanId;

  /// When this span started.
  final DateTime startedAt;

  /// Current trace context from the active async zone.
  static TraceContext? get current {
    final value = Zone.current[_traceContextZoneKey];
    return value is TraceContext ? value : null;
  }

  /// Creates a root trace context.
  factory TraceContext.root({DateTime? startedAt}) {
    return TraceContext._(
      traceId: _nextId('trace'),
      spanId: _nextId('span'),
      parentSpanId: null,
      startedAt: startedAt ?? DateTime.now().toUtc(),
    );
  }

  /// Runs [body] with [context] available as [current].
  static R run<R>(TraceContext context, R Function() body) {
    return runZoned(body, zoneValues: {_traceContextZoneKey: context});
  }

  /// Creates a child span in this trace.
  TraceContext child({DateTime? startedAt}) {
    return TraceContext._(
      traceId: traceId,
      spanId: _nextId('span'),
      parentSpanId: spanId,
      startedAt: startedAt ?? DateTime.now().toUtc(),
    );
  }

  static final Random _random = _createRandom();
  static final String _processEntropy = _createProcessEntropy();
  static int _sequence = 0;

  static String _nextId(String prefix) {
    _sequence += 1;
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final sequence = _sequence.toRadixString(36);
    final random = _random.nextInt(0x3fffffff).toRadixString(36);

    return '$prefix-$timestamp-$sequence-$_processEntropy-$random';
  }

  static Random _createRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random(DateTime.now().microsecondsSinceEpoch);
    }
  }

  static String _createProcessEntropy() {
    final objectEntropy = identityHashCode(Object()).toRadixString(36);
    final randomEntropy = _random.nextInt(0x3fffffff).toRadixString(36);

    return '$objectEntropy$randomEntropy';
  }
}
