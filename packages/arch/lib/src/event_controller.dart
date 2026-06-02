import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_dispatch_context.dart';
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
  bool _didLogControllerCreated = false;
  bool _didRegisterControllerDisposed = false;

  @mustCallSuper
  @override
  void runBuild() {
    _logControllerCreatedOnce();
    _registerControllerDisposedOnce();
    super.runBuild();
  }

  @override
  set state(AsyncValue<S> next) {
    final dispatchContext = EventDispatchContext.current;
    if (dispatchContext == null) {
      super.state = next;
      return;
    }

    AsyncValue<S>? previous;
    try {
      previous = super.state;
    } catch (_) {
      previous = null;
    }

    if (previous != null) {
      _logTransitionSafely(
        dispatchContext: dispatchContext,
        previous: previous,
        next: next,
      );
    }

    super.state = next;
  }

  @override
  Future<void> dispatch(E event) async {
    await future;

    final before = state;
    final startedAt = DateTime.now().toUtc();
    final safeControllerName = _safeControllerName();
    final safeEventName = _safeEventName(event);
    final safeMetadata = _safeDispatchMetadataFor(event);
    final parentTraceContext = TraceContext.current;
    final traceContext = parentTraceContext == null
        ? TraceContext.root(startedAt: startedAt)
        : parentTraceContext.child(startedAt: startedAt);
    final dispatchContext = EventDispatchContext(
      traceContext: traceContext,
      controllerName: safeControllerName,
      eventName: safeEventName,
      startedAt: startedAt,
      metadata: safeMetadata,
    );
    Object? error;
    StackTrace? stackTrace;

    _logEventStartedSafely(dispatchContext: dispatchContext, before: before);

    try {
      await EventDispatchContext.run(dispatchContext, () async {
        await onEvent(event);
      });
    } catch (caughtError, caughtStackTrace) {
      error = caughtError;
      stackTrace = caughtStackTrace;
      Error.throwWithStackTrace(caughtError, caughtStackTrace);
    } finally {
      _logEventFinishedSafely(
        dispatchContext: dispatchContext,
        before: before,
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

  /// Sanitized structured metadata recorded for all records from this controller.
  ///
  /// Use this for stable controller/provider identity such as provider names,
  /// provider variants, feature areas, or family arguments. Values must not
  /// include secrets, raw state payloads, or other sensitive application data.
  @protected
  Map<String, Object?> controllerMetadata() => const {};

  /// Optional payload-free state label recorded for state transitions.
  ///
  /// Do not return raw state objects, secrets, or private data.
  @protected
  String? stateLabel(AsyncValue<S> state) => null;

  /// Optional payload-free state metadata recorded for state transitions.
  ///
  /// Values must not include secrets, raw state payloads, or other sensitive
  /// application data.
  @protected
  Map<String, Object?> stateMetadata({
    required AsyncValue<S> previous,
    required AsyncValue<S> next,
  }) {
    return const {};
  }

  void _logControllerCreatedOnce() {
    if (_didLogControllerCreated) {
      return;
    }
    _didLogControllerCreated = true;

    final startedAt = DateTime.now().toUtc();
    final traceContext = TraceContext.root(startedAt: startedAt);
    _writeRecordSafely(
      EventLogRecord(
        phase: EventLogPhase.controllerCreated,
        traceContext: traceContext,
        controllerName: _safeControllerName(),
        startedAt: startedAt,
        metadata: _safeControllerMetadata(),
      ),
    );
  }

  void _registerControllerDisposedOnce() {
    if (_didRegisterControllerDisposed) {
      return;
    }
    _didRegisterControllerDisposed = true;

    final logger = _readLoggerSafely();
    ref.onDispose(() {
      final startedAt = DateTime.now().toUtc();
      final traceContext = TraceContext.root(startedAt: startedAt);
      _writeRecordToLoggerSafely(
        logger,
        EventLogRecord(
          phase: EventLogPhase.controllerDisposed,
          traceContext: traceContext,
          controllerName: _safeControllerName(),
          startedAt: startedAt,
          metadata: _safeControllerMetadata(),
        ),
      );
    });
  }

  void _logEventStartedSafely({
    required EventDispatchContext dispatchContext,
    required AsyncValue<S> before,
  }) {
    _writeRecordSafely(
      EventLogRecord(
        phase: EventLogPhase.eventStarted,
        traceContext: dispatchContext.traceContext,
        controllerName: dispatchContext.controllerName,
        eventName: dispatchContext.eventName,
        startedAt: dispatchContext.startedAt,
        previousStateKind: asyncValueKindOf(before),
        previousStateLabel: _safeStateLabel(before),
        metadata: dispatchContext.metadata,
      ),
    );
  }

  void _logTransitionSafely({
    required EventDispatchContext dispatchContext,
    required AsyncValue<S> previous,
    required AsyncValue<S> next,
  }) {
    _writeRecordSafely(
      EventLogRecord(
        phase: EventLogPhase.transition,
        traceContext: dispatchContext.traceContext,
        controllerName: dispatchContext.controllerName,
        eventName: dispatchContext.eventName,
        startedAt: DateTime.now().toUtc(),
        transitionIndex: dispatchContext.nextTransitionIndex(),
        previousStateKind: asyncValueKindOf(previous),
        nextStateKind: asyncValueKindOf(next),
        hasChanged: !identical(previous, next),
        previousStateLabel: _safeStateLabel(previous),
        nextStateLabel: _safeStateLabel(next),
        stateMetadata: _safeStateMetadata(previous: previous, next: next),
        metadata: dispatchContext.metadata,
      ),
    );
  }

  void _logEventFinishedSafely({
    required EventDispatchContext dispatchContext,
    required AsyncValue<S> before,
    required Object? error,
    required StackTrace? stackTrace,
  }) {
    try {
      final after = state;
      _writeRecordSafely(
        EventLogRecord(
          phase: error == null
              ? EventLogPhase.eventCompleted
              : EventLogPhase.eventFailed,
          traceContext: dispatchContext.traceContext,
          controllerName: dispatchContext.controllerName,
          eventName: dispatchContext.eventName,
          startedAt: dispatchContext.startedAt,
          duration: DateTime.now().toUtc().difference(
            dispatchContext.startedAt,
          ),
          previousStateKind: asyncValueKindOf(before),
          nextStateKind: asyncValueKindOf(after),
          hasChanged: !identical(before, after),
          previousStateLabel: _safeStateLabel(before),
          nextStateLabel: _safeStateLabel(after),
          stateMetadata: _safeStateMetadata(previous: before, next: after),
          error: error,
          stackTrace: stackTrace,
          metadata: dispatchContext.metadata,
        ),
      );
    } catch (_) {
      // Logging must never affect application flow.
    }
  }

  void _writeRecordSafely(EventLogRecord record) {
    final logger = _readLoggerSafely();
    _writeRecordToLoggerSafely(logger, record);
  }

  EventLogger? _readLoggerSafely() {
    try {
      return ref.read(eventLoggerProvider);
    } catch (_) {
      return null;
    }
  }

  void _writeRecordToLoggerSafely(EventLogger? logger, EventLogRecord record) {
    if (logger == null) {
      return;
    }

    try {
      logger.log(record);
    } catch (_) {
      // Logging must never affect application flow.
    }
  }

  String _safeControllerName() {
    try {
      return controllerName;
    } catch (_) {
      return runtimeType.toString();
    }
  }

  String _safeEventName(E event) {
    try {
      return eventName(event);
    } catch (_) {
      return event.runtimeType.toString();
    }
  }

  Map<String, Object?> _safeDispatchMetadataFor(E event) {
    return <String, Object?>{
      ..._safeControllerMetadata(),
      ..._safeMetadataFor(event),
    };
  }

  Map<String, Object?> _safeControllerMetadata() {
    try {
      return controllerMetadata();
    } catch (_) {
      return const {};
    }
  }

  Map<String, Object?> _safeMetadataFor(E event) {
    try {
      return metadataFor(event);
    } catch (_) {
      return const {};
    }
  }

  String? _safeStateLabel(AsyncValue<S> value) {
    try {
      return stateLabel(value);
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _safeStateMetadata({
    required AsyncValue<S> previous,
    required AsyncValue<S> next,
  }) {
    try {
      return stateMetadata(previous: previous, next: next);
    } catch (_) {
      return const {};
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
