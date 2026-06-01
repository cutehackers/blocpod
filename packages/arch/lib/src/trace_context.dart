import 'dart:async';

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
      traceId: _nextId(),
      spanId: _nextId(),
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
      spanId: _nextId(),
      parentSpanId: spanId,
      startedAt: startedAt ?? DateTime.now().toUtc(),
    );
  }

  static int _sequence = 0;

  static String _nextId() {
    _sequence += 1;
    return _sequence.toString();
  }
}
