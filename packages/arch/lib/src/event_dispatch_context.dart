import 'dart:async';

import 'metadata_snapshot.dart';
import 'trace_context.dart';

final Object _eventDispatchContextZoneKey = Object();

/// Event attribution stored in the active async zone during dispatch.
final class EventDispatchContext {
  EventDispatchContext({
    required this.traceContext,
    required this.controllerName,
    required this.eventName,
    required this.startedAt,
    Map<String, Object?> metadata = const {},
  }) : metadata = snapshotMetadata(metadata);

  final TraceContext traceContext;
  final String controllerName;
  final String eventName;
  final DateTime startedAt;
  final Map<String, Object?> metadata;

  int _transitionIndex = 0;

  /// Current event dispatch context from the active async zone.
  static EventDispatchContext? get current {
    final value = Zone.current[_eventDispatchContextZoneKey];
    return value is EventDispatchContext ? value : null;
  }

  /// Runs [body] with [context] and its trace context available in the zone.
  static R run<R>(EventDispatchContext context, R Function() body) {
    return TraceContext.run(context.traceContext, body, zoneValues: {_eventDispatchContextZoneKey: context});
  }

  /// Returns the next one-based transition index for this dispatch.
  int nextTransitionIndex() {
    _transitionIndex += 1;
    return _transitionIndex;
  }
}
