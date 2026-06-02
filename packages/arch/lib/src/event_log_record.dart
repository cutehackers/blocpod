import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trace_context.dart';

/// Payload-free state category for an [AsyncValue].
enum AsyncValueKind { loading, data, error }

/// Structured record for one event dispatch.
final class EventLogRecord {
  const EventLogRecord({
    required this.traceContext,
    required this.controllerName,
    required this.eventName,
    required this.startedAt,
    required this.duration,
    required this.beforeStateKind,
    required this.afterStateKind,
    required this.hasChanged,
    this.error,
    this.stackTrace,
    this.metadata = const {},
  });

  final TraceContext traceContext;
  final String controllerName;
  final String eventName;
  final DateTime startedAt;
  final Duration duration;
  final AsyncValueKind beforeStateKind;
  final AsyncValueKind afterStateKind;
  final bool hasChanged;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, Object?> metadata;
}

/// Returns the payload-free kind of [value].
AsyncValueKind asyncValueKindOf<S>(AsyncValue<S> value) {
  return switch (value) {
    AsyncLoading<S>() => AsyncValueKind.loading,
    AsyncError<S>() => AsyncValueKind.error,
    AsyncData<S>() => AsyncValueKind.data,
  };
}
