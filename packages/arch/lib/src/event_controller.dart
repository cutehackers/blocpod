import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_dispatch_context.dart';
import 'event_log_record.dart';
import 'event_logger.dart';
import 'observation_runtime.dart';
import 'trace_context.dart';

/// Public dispatch boundary for event-driven controllers.
abstract class EventController<E> {
  /// Dispatches [event] through the controller.
  Future<void> dispatch(E event);
}

/// Riverpod [AsyncNotifier] base class with a single event dispatch boundary.
abstract class EventControllerNotifier<S, E> extends AsyncNotifier<S> implements EventController<E> {
  final Object _dispatchOwner = Object();
  final Map<EventDispatchContext, _DispatchObservation<S>> _activeObservations = Map.identity();

  int _nextOwnedWriteOrdinal = 0;
  bool _didLogControllerCreated = false;
  bool _didLogInitialStateEstablished = false;
  bool _didRegisterControllerDisposed = false;

  @mustCallSuper
  @override
  void Function(void Function())? runBuild() {
    _logControllerCreatedOnce();
    _registerControllerDisposedOnce();
    final whenComplete = super.runBuild();
    _logInitialStateEstablishedOnce();
    return whenComplete == null
        ? null
        : (onComplete) {
            whenComplete(() {
              _logInitialStateEstablishedOnce();
              onComplete();
            });
          };
  }

  @override
  set state(AsyncValue<S> next) {
    final dispatchContext = EventDispatchContext.currentFor(_dispatchOwner);
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

    final observation = _activeObservations[dispatchContext];
    if (observation == null) {
      super.state = next;
      return;
    }

    _nextOwnedWriteOrdinal += 1;
    final writeOrdinal = _nextOwnedWriteOrdinal;
    final transitionIndex = previous == null ? null : dispatchContext.nextTransitionIndex();
    ObservationOccurrence? occurrence;
    if (previous != null) {
      try {
        occurrence = ObservationRuntime.capture();
      } catch (_) {
        // Observation allocation must not affect the state assignment.
      }
    }

    try {
      super.state = next;
    } catch (_) {
      if (occurrence != null) {
        ObservationRuntime.cancel(occurrence);
      }
      if (transitionIndex != null) {
        dispatchContext.cancelTransitionIndex(transitionIndex);
      }
      rethrow;
    }
    observation.recordOwnedState(next, writeOrdinal: writeOrdinal);

    if (previous != null && occurrence != null && transitionIndex != null) {
      _logTransitionSafely(
        dispatchContext: dispatchContext,
        occurrence: occurrence,
        transitionIndex: transitionIndex,
        previous: previous,
        next: next,
      );
    }
  }

  @override
  Future<void> dispatch(E event) async {
    await future;

    final before = state;
    final startedAt = DateTime.now().toUtc();
    final dispatchStopwatch = Stopwatch()..start();
    final safeControllerName = _safeControllerName();
    final safeEventName = _safeEventName(event);
    final safeMetadata = _safeDispatchMetadataFor(event);
    final parentDispatchContext = EventDispatchContext.current;
    final parentTraceContext = EventDispatchContext.parentTraceContext;
    final traceContext = parentTraceContext == null
        ? TraceContext.root(startedAt: startedAt)
        : parentTraceContext.child(startedAt: startedAt);
    final dispatchContext = EventDispatchContext(
      owner: _dispatchOwner,
      parent: parentDispatchContext,
      traceContext: traceContext,
      controllerName: safeControllerName,
      eventName: safeEventName,
      startedAt: startedAt,
      metadata: safeMetadata,
    );
    final observation = _DispatchObservation<S>(before);
    _activeObservations[dispatchContext] = observation;
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
      dispatchContext.close();
      dispatchStopwatch.stop();
      final terminalOccurrence = ObservationRuntime.capture();
      try {
        final outcome = observation.outcome;
        _foldOwnedOutcomeIntoParent(dispatchContext, observation);
        _activeObservations.remove(dispatchContext);
        _logEventFinishedSafely(
          dispatchContext: dispatchContext,
          occurrence: terminalOccurrence,
          duration: dispatchStopwatch.elapsed,
          stateAtStart: observation.stateAtStart,
          outcome: outcome,
          error: error,
          stackTrace: stackTrace,
        );
      } catch (_) {
        ObservationRuntime.cancel(terminalOccurrence);
        rethrow;
      }
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

  /// Optional payload-free state label recorded for initialization and transitions.
  ///
  /// Do not return raw state objects, secrets, or private data.
  @protected
  String? stateLabel(AsyncValue<S> state) => null;

  /// Optional payload-free state metadata recorded for initialization and transitions.
  ///
  /// During initialization, [previous] and [next] are the same established state.
  ///
  /// Values must not include secrets, raw state payloads, or other sensitive
  /// application data.
  @protected
  Map<String, Object?> stateMetadata({required AsyncValue<S> previous, required AsyncValue<S> next}) {
    return const {};
  }

  void _logControllerCreatedOnce() {
    if (_didLogControllerCreated) {
      return;
    }
    _didLogControllerCreated = true;

    final occurrence = ObservationRuntime.capture();
    _publishRecordSafely(occurrence, () {
      final startedAt = occurrence.occurredAt;
      return EventLogRecord(
        phase: EventLogPhase.controllerCreated,
        traceContext: TraceContext.root(startedAt: startedAt),
        controllerName: _safeControllerName(),
        startedAt: startedAt,
        occurredAt: occurrence.occurredAt,
        recordSequence: occurrence.recordSequence,
        metadata: _safeControllerMetadata(),
      );
    });
  }

  void _logInitialStateEstablishedOnce() {
    if (_didLogInitialStateEstablished) {
      return;
    }

    try {
      final initialized = state;
      if (initialized is AsyncLoading<S>) {
        return;
      }
      _didLogInitialStateEstablished = true;
      final (error, stackTrace) = switch (initialized) {
        AsyncError<S>(:final error, :final stackTrace) => (error, stackTrace),
        _ => (null, null),
      };
      final occurrence = ObservationRuntime.capture();
      _publishRecordSafely(occurrence, () {
        final startedAt = occurrence.occurredAt;
        return EventLogRecord(
          phase: EventLogPhase.initialStateEstablished,
          traceContext: TraceContext.root(startedAt: startedAt),
          controllerName: _safeControllerName(),
          startedAt: startedAt,
          occurredAt: occurrence.occurredAt,
          recordSequence: occurrence.recordSequence,
          nextStateKind: asyncValueKindOf(initialized),
          nextStateLabel: _safeStateLabel(initialized),
          stateMetadata: _safeStateMetadata(previous: initialized, next: initialized),
          error: error,
          stackTrace: stackTrace,
          metadata: _safeControllerMetadata(),
        );
      });
    } catch (_) {
      // Logging must never affect application flow.
    }
  }

  void _registerControllerDisposedOnce() {
    if (_didRegisterControllerDisposed) {
      return;
    }
    _didRegisterControllerDisposed = true;

    final logger = _readLoggerSafely();
    ref.onDispose(() {
      final occurrence = ObservationRuntime.capture();
      _publishRecordToLoggerSafely(occurrence, logger, () {
        final startedAt = occurrence.occurredAt;
        return EventLogRecord(
          phase: EventLogPhase.controllerDisposed,
          traceContext: TraceContext.root(startedAt: startedAt),
          controllerName: _safeControllerName(),
          startedAt: startedAt,
          occurredAt: occurrence.occurredAt,
          recordSequence: occurrence.recordSequence,
          metadata: _safeControllerMetadata(),
        );
      });
    });
  }

  void _logEventStartedSafely({required EventDispatchContext dispatchContext, required AsyncValue<S> before}) {
    final occurrence = ObservationRuntime.capture();
    _publishRecordSafely(occurrence, () {
      return EventLogRecord(
        phase: EventLogPhase.eventStarted,
        traceContext: dispatchContext.traceContext,
        controllerName: dispatchContext.controllerName,
        eventName: dispatchContext.eventName,
        startedAt: dispatchContext.startedAt,
        occurredAt: occurrence.occurredAt,
        recordSequence: occurrence.recordSequence,
        previousStateKind: asyncValueKindOf(before),
        previousStateLabel: _safeStateLabel(before),
        metadata: dispatchContext.metadata,
      );
    });
  }

  void _logTransitionSafely({
    required EventDispatchContext dispatchContext,
    required ObservationOccurrence occurrence,
    required int transitionIndex,
    required AsyncValue<S> previous,
    required AsyncValue<S> next,
  }) {
    _publishRecordSafely(occurrence, () {
      return EventLogRecord(
        phase: EventLogPhase.transition,
        traceContext: dispatchContext.traceContext,
        controllerName: dispatchContext.controllerName,
        eventName: dispatchContext.eventName,
        startedAt: dispatchContext.startedAt,
        occurredAt: occurrence.occurredAt,
        recordSequence: occurrence.recordSequence,
        transitionIndex: transitionIndex,
        previousStateKind: asyncValueKindOf(previous),
        nextStateKind: asyncValueKindOf(next),
        hasChanged: !identical(previous, next),
        previousStateLabel: _safeStateLabel(previous),
        nextStateLabel: _safeStateLabel(next),
        stateMetadata: _safeStateMetadata(previous: previous, next: next),
        metadata: dispatchContext.metadata,
      );
    });
  }

  void _logEventFinishedSafely({
    required EventDispatchContext dispatchContext,
    required ObservationOccurrence occurrence,
    required Duration duration,
    required AsyncValue<S> stateAtStart,
    required AsyncValue<S> outcome,
    required Object? error,
    required StackTrace? stackTrace,
  }) {
    _publishRecordSafely(occurrence, () {
      return EventLogRecord(
        phase: error == null ? EventLogPhase.eventCompleted : EventLogPhase.eventFailed,
        traceContext: dispatchContext.traceContext,
        controllerName: dispatchContext.controllerName,
        eventName: dispatchContext.eventName,
        startedAt: dispatchContext.startedAt,
        occurredAt: occurrence.occurredAt,
        recordSequence: occurrence.recordSequence,
        duration: duration,
        previousStateKind: asyncValueKindOf(stateAtStart),
        nextStateKind: asyncValueKindOf(outcome),
        hasChanged: !identical(stateAtStart, outcome),
        previousStateLabel: _safeStateLabel(stateAtStart),
        nextStateLabel: _safeStateLabel(outcome),
        stateMetadata: _safeStateMetadata(previous: stateAtStart, next: outcome),
        error: error,
        stackTrace: stackTrace,
        metadata: dispatchContext.metadata,
      );
    });
  }

  void _foldOwnedOutcomeIntoParent(EventDispatchContext dispatchContext, _DispatchObservation<S> observation) {
    if (!observation.hasOwnedOutcome) {
      return;
    }

    final parent = dispatchContext.parent;
    if (parent == null || !parent.isActive || !parent.owns(_dispatchOwner)) {
      return;
    }

    _activeObservations[parent]?.recordOwnedState(
      observation.outcome,
      writeOrdinal: observation.latestOwnedWriteOrdinal!,
    );
  }

  void _publishRecordSafely(ObservationOccurrence occurrence, EventLogRecord Function() buildRecord) {
    try {
      final record = buildRecord();
      final logger = _readLoggerSafely();
      ObservationRuntime.publish(occurrence, logger, record);
    } catch (_) {
      ObservationRuntime.cancel(occurrence);
    }
  }

  EventLogger? _readLoggerSafely() {
    try {
      return ref.read(eventLoggerProvider);
    } catch (_) {
      return null;
    }
  }

  void _publishRecordToLoggerSafely(
    ObservationOccurrence occurrence,
    EventLogger? logger,
    EventLogRecord Function() buildRecord,
  ) {
    try {
      final record = buildRecord();
      ObservationRuntime.publish(occurrence, logger, record);
    } catch (_) {
      ObservationRuntime.cancel(occurrence);
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
    return <String, Object?>{..._safeControllerMetadata(), ..._safeMetadataFor(event)};
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

  Map<String, Object?> _safeStateMetadata({required AsyncValue<S> previous, required AsyncValue<S> next}) {
    try {
      return stateMetadata(previous: previous, next: next);
    } catch (_) {
      return const {};
    }
  }
}

final class _DispatchObservation<S> {
  _DispatchObservation(this.stateAtStart);

  final AsyncValue<S> stateAtStart;
  AsyncValue<S>? latestOwnedState;
  int? latestOwnedWriteOrdinal;
  bool hasOwnedOutcome = false;

  AsyncValue<S> get outcome => latestOwnedState ?? stateAtStart;

  void recordOwnedState(AsyncValue<S> next, {required int writeOrdinal}) {
    final currentOrdinal = latestOwnedWriteOrdinal;
    if (currentOrdinal != null && writeOrdinal <= currentOrdinal) {
      return;
    }

    latestOwnedState = next;
    latestOwnedWriteOrdinal = writeOrdinal;
    hasOwnedOutcome = true;
  }
}

/// Dispatch helper for providers and other non-widget Riverpod code.
extension RefEventDispatcherX on Ref {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(AsyncNotifierProvider<N, S> provider, E event) {
    return read(provider.notifier).dispatch(event);
  }
}

/// Dispatch helper for widgets.
extension WidgetRefEventDispatcherX on WidgetRef {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(AsyncNotifierProvider<N, S> provider, E event) {
    return read(provider.notifier).dispatch(event);
  }
}
