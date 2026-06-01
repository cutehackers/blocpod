import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_log_record.dart';
import 'event_logger.dart';
import 'trace_context.dart';

/// Public dispatch boundary for event-driven controllers.
abstract class EventController<E> {
  /// Dispatches [event] through the controller.
  Future<void> dispatch(E event);
}

/// Riverpod [AsyncNotifier] base class with a single event dispatch boundary.
abstract class EventControllerNotifier<S, E> extends AsyncNotifier<S>
    implements EventController<E> {
  @override
  Future<void> dispatch(E event) async {
    await future;

    final before = state;
    final startedAt = DateTime.now().toUtc();
    final parentTraceContext = TraceContext.current;
    final traceContext = parentTraceContext == null
        ? TraceContext.root(startedAt: startedAt)
        : parentTraceContext.child(startedAt: startedAt);
    Object? error;
    StackTrace? stackTrace;

    try {
      await TraceContext.run(traceContext, () async {
        await onEvent(event);
      });
    } catch (caughtError, caughtStackTrace) {
      error = caughtError;
      stackTrace = caughtStackTrace;
      Error.throwWithStackTrace(caughtError, caughtStackTrace);
    } finally {
      _logSafely(
        event: event,
        before: before,
        traceContext: traceContext,
        startedAt: startedAt,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handles one dispatched event.
  @protected
  Future<void> onEvent(E event);

  /// Name recorded for this controller.
  @protected
  String get controllerName => runtimeType.toString();

  /// Name recorded for [event].
  @protected
  String eventName(E event) => event.runtimeType.toString();

  /// Sanitized structured metadata recorded for [event].
  ///
  /// Values must not include secrets, raw state payloads, or other sensitive
  /// application data.
  @protected
  Map<String, Object?> metadataFor(E event) => const {};

  void _logSafely({
    required E event,
    required AsyncValue<S> before,
    required TraceContext traceContext,
    required DateTime startedAt,
    required Object? error,
    required StackTrace? stackTrace,
  }) {
    try {
      final after = state;
      final record = EventLogRecord(
        traceContext: traceContext,
        controllerName: controllerName,
        eventName: eventName(event),
        startedAt: startedAt,
        duration: DateTime.now().toUtc().difference(startedAt),
        beforeStateKind: asyncValueKindOf(before),
        afterStateKind: asyncValueKindOf(after),
        hasChanged: before != after,
        error: error,
        stackTrace: stackTrace,
        metadata: metadataFor(event),
      );

      ref.read(eventLoggerProvider).log(record);
    } catch (_) {
      // Logging must never affect application flow.
    }
  }
}

/// Dispatch helper for providers and other non-widget Riverpod code.
extension RefEventDispatcherX on Ref {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) {
    return read(provider.notifier).dispatch(event);
  }
}

/// Dispatch helper for widgets.
extension WidgetRefEventDispatcherX on WidgetRef {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) {
    return read(provider.notifier).dispatch(event);
  }
}
