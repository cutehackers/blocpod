import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'metadata_snapshot.dart';
import 'trace_context.dart';

/// Payload-free state category for an [AsyncValue].
enum AsyncValueKind { loading, data, error }

/// Observable lifecycle phase for a Blocpod controller.
enum EventLogPhase { controllerCreated, eventStarted, transition, eventCompleted, eventFailed, controllerDisposed }

/// Structured, payload-free observation record for Blocpod controllers.
final class EventLogRecord {
  EventLogRecord({
    required this.phase,
    required this.traceContext,
    required this.controllerName,
    this.eventName,
    required this.startedAt,
    this.duration,
    this.transitionIndex,
    this.previousStateKind,
    this.nextStateKind,
    this.hasChanged,
    this.previousStateLabel,
    this.nextStateLabel,
    Map<String, Object?> stateMetadata = const {},
    this.error,
    this.stackTrace,
    Map<String, Object?> metadata = const {},
  }) : stateMetadata = snapshotMetadata(stateMetadata),
       metadata = snapshotMetadata(metadata);

  final EventLogPhase phase;
  final TraceContext traceContext;
  final String controllerName;
  final String? eventName;
  final DateTime startedAt;
  final Duration? duration;
  final int? transitionIndex;
  final AsyncValueKind? previousStateKind;
  final AsyncValueKind? nextStateKind;
  final bool? hasChanged;
  final String? previousStateLabel;
  final String? nextStateLabel;
  final Map<String, Object?> stateMetadata;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> metadata;

  /// Compatibility alias for earlier dispatch-completion records.
  AsyncValueKind? get beforeStateKind => previousStateKind;

  /// Compatibility alias for earlier dispatch-completion records.
  AsyncValueKind? get afterStateKind => nextStateKind;
}

/// Returns the payload-free kind of [value].
AsyncValueKind asyncValueKindOf<S>(AsyncValue<S> value) {
  return switch (value) {
    AsyncLoading<S>() => AsyncValueKind.loading,
    AsyncError<S>() => AsyncValueKind.error,
    AsyncData<S>() => AsyncValueKind.data,
  };
}
