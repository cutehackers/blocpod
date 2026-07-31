import 'dart:async';

import 'metadata_snapshot.dart';
import 'trace_context.dart';

final Object _eventDispatchContextZoneKey = Object();

/// Event attribution stored in the active async zone during dispatch.
final class EventDispatchContext {
  EventDispatchContext({
    required this.owner,
    this.parent,
    required this.traceContext,
    required this.controllerName,
    required this.eventName,
    required this.startedAt,
    Map<String, Object?> metadata = const {},
  }) : metadata = snapshotMetadata(metadata);

  final Object owner;
  final EventDispatchContext? parent;
  final TraceContext traceContext;
  final String controllerName;
  final String eventName;
  final DateTime startedAt;
  final Map<String, Object?> metadata;

  bool _isActive = true;
  int _transitionIndex = 0;

  /// Whether this dispatch can still attribute state changes.
  bool get isActive => _isActive;

  /// Whether [candidate] is this dispatch's controller owner.
  bool owns(Object candidate) => identical(owner, candidate);

  /// Closes this dispatch context.
  void close() {
    _isActive = false;
  }

  static EventDispatchContext? get _ambientContext {
    final value = Zone.current[_eventDispatchContextZoneKey];
    return value is EventDispatchContext ? value : null;
  }

  /// Current event dispatch context from the active async zone.
  static EventDispatchContext? get current {
    final context = _ambientContext;
    if (context == null || !context.isActive) {
      return null;
    }
    return context;
  }

  /// Current active dispatch context when it belongs to [owner].
  static EventDispatchContext? currentFor(Object owner) {
    final context = current;
    if (context == null || !context.owns(owner)) {
      return null;
    }
    return context;
  }

  /// Whether the zone contains an active or closed dispatch context.
  static bool get hasAmbientContext => _ambientContext != null;

  /// Runs [body] with [context] and its trace context available in the zone.
  static R run<R>(EventDispatchContext context, R Function() body) {
    return TraceContext.run(
      context.traceContext,
      body,
      zoneValues: {_eventDispatchContextZoneKey: context},
    );
  }

  /// Runs [body] with dispatch and trace contexts masked from the zone.
  static R runWithoutContext<R>(R Function() body) {
    return runWithoutTraceContext(
      body,
      zoneValues: {_eventDispatchContextZoneKey: null},
    );
  }

  /// Returns the next one-based transition index for this dispatch.
  int nextTransitionIndex() {
    _transitionIndex += 1;
    return _transitionIndex;
  }
}
