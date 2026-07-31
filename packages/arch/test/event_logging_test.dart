import 'dart:async';

import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch/src/event_dispatch_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class LoggingEvent {
  const LoggingEvent();
}

final class IncrementEvent extends LoggingEvent {
  const IncrementEvent();
}

final class ThrowEvent extends LoggingEvent {
  const ThrowEvent();
}

final class ParentEvent extends LoggingEvent {
  const ParentEvent();
}

final class ChildEvent extends LoggingEvent {
  const ChildEvent();
}

final class ThrowMetadataEvent extends LoggingEvent {
  const ThrowMetadataEvent();
}

final class ThrowEventAndMetadataEvent extends LoggingEvent {
  const ThrowEventAndMetadataEvent();
}

final class ThrowAfterStateEvent extends LoggingEvent {
  const ThrowAfterStateEvent();
}

final class MultiStepEvent extends LoggingEvent {
  const MultiStepEvent();
}

final class ThrowStateSummaryEvent extends LoggingEvent {
  const ThrowStateSummaryEvent();
}

final class ConcurrentFirstEvent extends LoggingEvent {
  const ConcurrentFirstEvent();
}

final class ConcurrentSecondEvent extends LoggingEvent {
  const ConcurrentSecondEvent();
}

final class GatedPhaseEvent extends LoggingEvent {
  const GatedPhaseEvent({
    required this.name,
    required this.entered,
    required this.releaseTransition,
    required this.transitioned,
    required this.releaseCompletion,
    required this.value,
  });

  final String name;
  final Completer<void> entered;
  final Future<void> releaseTransition;
  final Completer<void> transitioned;
  final Future<void> releaseCompletion;
  final int value;
}

final class GatedFailureEvent extends LoggingEvent {
  const GatedFailureEvent({required this.entered, required this.release, required this.error});

  final Completer<void> entered;
  final Future<void> release;
  final StateError error;
}

final class NoWriteEvent extends LoggingEvent {
  const NoWriteEvent({required this.entered, required this.release});

  final Completer<void> entered;
  final Future<void> release;
}

final class ParentWithoutLaterWriteEvent extends LoggingEvent {
  const ParentWithoutLaterWriteEvent({required this.childSettled, required this.release});

  final Completer<void> childSettled;
  final Future<void> release;
}

final class ParentWriteAfterChildEvent extends LoggingEvent {
  const ParentWriteAfterChildEvent({required this.wrote, required this.release});

  final Completer<void> wrote;
  final Future<void> release;
}

final class ParentWritesWhileChildPendingEvent extends LoggingEvent {
  const ParentWritesWhileChildPendingEvent({
    required this.childWrote,
    required this.parentWrote,
    required this.releaseChild,
  });

  final Completer<void> childWrote;
  final Completer<void> parentWrote;
  final Future<void> releaseChild;
}

final class ReverseCompletionChildrenEvent extends LoggingEvent {
  const ReverseCompletionChildrenEvent({
    required this.firstWrote,
    required this.secondWrote,
    required this.releaseFirst,
    required this.releaseSecond,
    required this.secondCompleted,
  });

  final Completer<void> firstWrote;
  final Completer<void> secondWrote;
  final Future<void> releaseFirst;
  final Future<void> releaseSecond;
  final Completer<void> secondCompleted;
}

final class OrderedChildEvent extends LoggingEvent {
  const OrderedChildEvent({required this.value, required this.wrote, required this.release});

  final int value;
  final Completer<void> wrote;
  final Future<void> release;
}

final class CrossControllerParentEvent extends LoggingEvent {
  const CrossControllerParentEvent(this.dispatchChild);

  final Future<void> Function() dispatchChild;
}

final class FireAndForgetParentEvent extends LoggingEvent {
  const FireAndForgetParentEvent({
    required this.childStarted,
    required this.releaseChild,
    required this.childCompleted,
  });

  final Completer<void> childStarted;
  final Future<void> releaseChild;
  final Completer<void> childCompleted;
}

final class DelayedChildEvent extends LoggingEvent {
  const DelayedChildEvent({required this.started, required this.release});

  final Completer<void> started;
  final Future<void> release;
}

final class ThrowOwnedOutcomeEvent extends LoggingEvent {
  const ThrowOwnedOutcomeEvent({required this.afterWrite, required this.release, required this.error});

  final Completer<void> afterWrite;
  final Future<void> release;
  final StateError error;
}

final class InheritedWriteThenThrowEvent extends LoggingEvent {
  const InheritedWriteThenThrowEvent({required this.trigger, required this.completed, required this.error});

  final Future<void> trigger;
  final Completer<void> completed;
  final StateError error;
}

final class DirectWriteEvent extends LoggingEvent {
  const DirectWriteEvent(this.write);

  final void Function() write;
}

final class InheritedWriteEvent extends LoggingEvent {
  const InheritedWriteEvent({required this.trigger, required this.completed});

  final Future<void> trigger;
  final Completer<void> completed;
}

final class InheritedDispatchEvent extends LoggingEvent {
  const InheritedDispatchEvent({required this.trigger, required this.dispatch, required this.completed});

  final Future<void> trigger;
  final Future<void> Function() dispatch;
  final Completer<void> completed;
}

final class RejectingStateEvent {
  const RejectingStateEvent(this.value);

  final int value;
}

final loggingProvider = AsyncNotifierProvider<LoggingController, int>(LoggingController.new);

final otherLoggingProvider = AsyncNotifierProvider<LoggingController, int>(LoggingController.new);

final rejectingStateProvider = AsyncNotifierProvider<RejectingStateController, int>(RejectingStateController.new);

final explodingEqualityProvider = AsyncNotifierProvider<ExplodingEqualityController, ExplodingEquality>(
  ExplodingEqualityController.new,
);

final failingBuildProvider = AsyncNotifierProvider<FailingBuildController, int>(
  FailingBuildController.new,
  retry: (_, _) => null,
);

final synchronousFailingBuildProvider = AsyncNotifierProvider<SynchronousFailingBuildController, int>(
  SynchronousFailingBuildController.new,
  retry: (_, _) => null,
);

final retryThenSuccessProvider = AsyncNotifierProvider<RetryThenSuccessController, int>(
  RetryThenSuccessController.new,
  retry: (retryCount, _) => retryCount == 0 ? Duration.zero : null,
);

final retryExhaustionProvider = AsyncNotifierProvider<RetryExhaustionController, int>(
  RetryExhaustionController.new,
  retry: (retryCount, _) => retryCount == 0 ? Duration.zero : null,
);

final cancellableBuildProvider = AsyncNotifierProvider<CancellableBuildController, int>(
  CancellableBuildController.new,
  retry: (_, _) => null,
);

final plainSyncProvider = AsyncNotifierProvider<PlainSyncController, int>(PlainSyncController.new);

final rebuildingProvider = AsyncNotifierProvider<RebuildingController, int>(RebuildingController.new);

final class LoggingController extends EventControllerNotifier<int, LoggingEvent> {
  @override
  Future<int> build() async {
    return 0;
  }

  @override
  Future<void> onEvent(LoggingEvent event) async {
    switch (event) {
      case IncrementEvent():
        final value = switch (state) {
          AsyncData(:final value) => value,
          _ => 0,
        };
        state = AsyncData(value + 1);
      case ThrowEvent():
        throw StateError('boom');
      case ParentEvent():
        await dispatch(const ChildEvent());
        state = const AsyncData(10);
      case ChildEvent():
        state = const AsyncData(5);
      case ThrowMetadataEvent():
        state = const AsyncData(20);
      case ThrowEventAndMetadataEvent():
        throw StateError('handler failed');
      case ThrowAfterStateEvent():
        state = const AsyncData(30);
        throw StateError('state changed then failed');
      case MultiStepEvent():
        state = const AsyncData(1);
        state = const AsyncLoading<int>();
        await Future<void>.delayed(Duration.zero);
        state = const AsyncData(3);
      case ThrowStateSummaryEvent():
        state = const AsyncData(404);
      case ConcurrentFirstEvent():
        await Future<void>.delayed(Duration.zero);
        state = const AsyncData(100);
      case ConcurrentSecondEvent():
        state = const AsyncData(200);
        await Future<void>.delayed(Duration.zero);
      case GatedPhaseEvent(
        :final entered,
        :final releaseTransition,
        :final transitioned,
        :final releaseCompletion,
        :final value,
      ):
        entered.complete();
        await releaseTransition;
        state = AsyncData(value);
        transitioned.complete();
        await releaseCompletion;
      case GatedFailureEvent(:final entered, :final release, :final error):
        entered.complete();
        await release;
        throw error;
      case NoWriteEvent(:final entered, :final release):
        entered.complete();
        await release;
      case ParentWithoutLaterWriteEvent(:final childSettled, :final release):
        await dispatch(const ChildEvent());
        childSettled.complete();
        await release;
      case ParentWriteAfterChildEvent(:final wrote, :final release):
        await dispatch(const ChildEvent());
        state = const AsyncData(10);
        wrote.complete();
        await release;
      case ParentWritesWhileChildPendingEvent(:final childWrote, :final parentWrote, :final releaseChild):
        final child = dispatch(OrderedChildEvent(value: 1, wrote: childWrote, release: releaseChild));
        await childWrote.future;
        state = const AsyncData(2);
        parentWrote.complete();
        await child;
      case ReverseCompletionChildrenEvent(
        :final firstWrote,
        :final secondWrote,
        :final releaseFirst,
        :final releaseSecond,
        :final secondCompleted,
      ):
        final first = dispatch(OrderedChildEvent(value: 1, wrote: firstWrote, release: releaseFirst));
        await firstWrote.future;
        final second = dispatch(OrderedChildEvent(value: 2, wrote: secondWrote, release: releaseSecond));
        await secondWrote.future;
        unawaited(second.whenComplete(secondCompleted.complete));
        await Future.wait(<Future<void>>[first, second]);
      case OrderedChildEvent(:final value, :final wrote, :final release):
        state = AsyncData(value);
        wrote.complete();
        await release;
      case CrossControllerParentEvent(:final dispatchChild):
        await dispatchChild();
      case FireAndForgetParentEvent(:final childStarted, :final releaseChild, :final childCompleted):
        unawaited(
          dispatch(
            DelayedChildEvent(started: childStarted, release: releaseChild),
          ).whenComplete(childCompleted.complete),
        );
        await childStarted.future;
      case DelayedChildEvent(:final started, :final release):
        started.complete();
        await release;
        state = const AsyncData(70);
      case ThrowOwnedOutcomeEvent(:final afterWrite, :final release, :final error):
        state = const AsyncData(30);
        afterWrite.complete();
        await release;
        throw error;
      case InheritedWriteThenThrowEvent(:final trigger, :final completed, :final error):
        unawaited(
          trigger.then((_) {
            state = const AsyncData(88);
            completed.complete();
          }),
        );
        throw error;
      case DirectWriteEvent(:final write):
        write();
      case InheritedWriteEvent(:final trigger, :final completed):
        unawaited(
          trigger.then((_) {
            state = const AsyncData(88);
            completed.complete();
          }),
        );
      case InheritedDispatchEvent(:final trigger, :final dispatch, :final completed):
        unawaited(() async {
          await trigger;
          await dispatch();
          completed.complete();
        }());
    }
  }

  void setDirectly(int value) {
    state = AsyncData(value);
  }

  @override
  Map<String, Object?> metadataFor(LoggingEvent event) {
    return switch (event) {
      IncrementEvent() => const {'kind': 'increment'},
      ThrowEvent() => const {'kind': 'throw'},
      ParentEvent() => const {'kind': 'parent'},
      ChildEvent() => const {'kind': 'child'},
      ThrowMetadataEvent() => throw StateError('metadata failed'),
      ThrowEventAndMetadataEvent() => throw StateError('metadata failed'),
      ThrowAfterStateEvent() => const {'kind': 'throw-after-state'},
      MultiStepEvent() => const {'kind': 'multi-step'},
      ThrowStateSummaryEvent() => const {'kind': 'throw-state-summary'},
      ConcurrentFirstEvent() => const {'kind': 'concurrent-first'},
      ConcurrentSecondEvent() => const {'kind': 'concurrent-second'},
      GatedPhaseEvent(:final name) => <String, Object?>{'kind': 'gated-phase', 'name': name},
      GatedFailureEvent() => const {'kind': 'gated-failure'},
      NoWriteEvent() => const {'kind': 'no-write'},
      ParentWithoutLaterWriteEvent() => const {'kind': 'parent-without-later-write'},
      ParentWriteAfterChildEvent() => const {'kind': 'parent-write-after-child'},
      ParentWritesWhileChildPendingEvent() => const {'kind': 'parent-writes-while-child-pending'},
      ReverseCompletionChildrenEvent() => const {'kind': 'reverse-completion-children'},
      OrderedChildEvent() => const {'kind': 'ordered-child'},
      CrossControllerParentEvent() => const {'kind': 'cross-controller-parent'},
      FireAndForgetParentEvent() => const {'kind': 'fire-and-forget-parent'},
      DelayedChildEvent() => const {'kind': 'delayed-child'},
      ThrowOwnedOutcomeEvent() => const {'kind': 'throw-owned-outcome'},
      InheritedWriteThenThrowEvent() => const {'kind': 'inherited-write-then-throw'},
      DirectWriteEvent() => const {'kind': 'direct-write'},
      InheritedWriteEvent() => const {'kind': 'inherited-write'},
      InheritedDispatchEvent() => const {'kind': 'inherited-dispatch'},
    };
  }

  @override
  Map<String, Object?> controllerMetadata() {
    return const {'controllerScope': 'sample-logging'};
  }

  @override
  String? stateLabel(AsyncValue<int> state) {
    return switch (state) {
      AsyncLoading<int>() => 'loading',
      AsyncError<int>() => 'error',
      AsyncData<int>(value: 404) => throw StateError('state label failed'),
      AsyncData<int>(:final value) => 'value:$value',
    };
  }

  @override
  Map<String, Object?> stateMetadata({required AsyncValue<int> previous, required AsyncValue<int> next}) {
    if (next case AsyncData<int>(value: 404)) {
      throw StateError('state metadata failed');
    }
    return <String, Object?>{'previousKind': asyncValueKindOf(previous).name, 'nextKind': asyncValueKindOf(next).name};
  }
}

final class ExplodingEquality {
  const ExplodingEquality(this.value);

  final int value;

  @override
  bool operator ==(Object other) {
    throw StateError('payload equality should not be called');
  }

  @override
  int get hashCode => value.hashCode;
}

final class ExplodingEqualityEvent {
  const ExplodingEqualityEvent();
}

final class ExplodingEqualityController extends EventControllerNotifier<ExplodingEquality, ExplodingEqualityEvent> {
  @override
  Future<ExplodingEquality> build() async {
    return const ExplodingEquality(0);
  }

  @override
  Future<void> onEvent(ExplodingEqualityEvent event) async {
    state = const AsyncData(ExplodingEquality(1));
  }

  @override
  bool updateShouldNotify(AsyncValue<ExplodingEquality> previous, AsyncValue<ExplodingEquality> next) {
    return !identical(previous, next);
  }
}

final class RejectingStateController extends EventControllerNotifier<int, RejectingStateEvent> {
  final rejection = StateError('assignment rejected');

  @override
  Future<int> build() async => 0;

  @override
  Future<void> onEvent(RejectingStateEvent event) async {
    state = AsyncData(event.value);
  }

  @override
  String eventName(RejectingStateEvent event) {
    return event.value == 1 ? 'RejectingStateEvent' : 'RecoveryStateEvent';
  }

  @override
  String stateLabel(AsyncValue<int> state) {
    return switch (state) {
      AsyncLoading<int>() => 'loading',
      AsyncError<int>() => 'error',
      AsyncData<int>(:final value) => 'value:$value',
    };
  }

  @override
  bool updateShouldNotify(AsyncValue<int> previous, AsyncValue<int> next) {
    if (next case AsyncData<int>(value: 1)) {
      throw rejection;
    }
    return true;
  }
}

final class FailingBuildController extends EventControllerNotifier<int, LoggingEvent> {
  @override
  Future<int> build() async {
    throw StateError('restore failed');
  }

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}

final class SynchronousFailingBuildController extends EventControllerNotifier<int, LoggingEvent> {
  @override
  int build() {
    throw StateError('sync restore failed');
  }

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}

final class RetryThenSuccessController extends EventControllerNotifier<int, LoggingEvent> {
  int attempts = 0;

  @override
  Future<int> build() async {
    attempts++;
    if (attempts == 1) {
      throw Exception('retry once');
    }
    return 42;
  }

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}

final class RetryExhaustionController extends EventControllerNotifier<int, LoggingEvent> {
  int attempts = 0;

  @override
  Future<int> build() async {
    attempts++;
    throw Exception('retry failed $attempts');
  }

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}

final class CancellableBuildController extends EventControllerNotifier<int, LoggingEvent> {
  final completions = <Completer<int>>[];

  @override
  Future<int> build() {
    final completion = Completer<int>();
    completions.add(completion);
    return completion.future;
  }

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}

final class PlainSyncController extends EventControllerNotifier<int, LoggingEvent> {
  @override
  int build() => 7;

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}

final class RebuildingController extends EventControllerNotifier<int, LoggingEvent> {
  int _buildCount = 0;

  @override
  int build() => ++_buildCount;

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}

final class CollectingEventLogger implements EventLogger {
  final records = <EventLogRecord>[];

  @override
  void log(EventLogRecord record) {
    records.add(record);
  }
}

final class ThrowingEventLogger implements EventLogger {
  @override
  void log(EventLogRecord record) {
    throw StateError('logger failed');
  }
}

final class CallbackEventLogger implements EventLogger {
  CallbackEventLogger(this.onRecord);

  final void Function(EventLogRecord record) onRecord;

  @override
  void log(EventLogRecord record) {
    onRecord(record);
  }
}

final class _EqualOwner {
  @override
  bool operator ==(Object other) => other is _EqualOwner;

  @override
  int get hashCode => 0;
}

void main() {
  test('default logger is no-op and dispatch still succeeds', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 1));
  });

  test('async build logs its initialized state through existing summary hooks', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.future);

    expect(logger.records.map((record) => record.phase), <EventLogPhase>[
      EventLogPhase.controllerCreated,
      EventLogPhase.initialStateEstablished,
    ]);
    final initialized = logger.records.singleWhere((record) => record.phase == EventLogPhase.initialStateEstablished);
    expect(initialized.controllerName, 'LoggingController');
    expect(initialized.eventName, isNull);
    expect(initialized.previousStateKind, isNull);
    expect(initialized.previousStateLabel, isNull);
    expect(initialized.nextStateKind, AsyncValueKind.data);
    expect(initialized.nextStateLabel, 'value:0');
    expect(initialized.hasChanged, isNull);
    expect(initialized.duration, isNull);
    expect(initialized.transitionIndex, isNull);
    expect(initialized.stateMetadata, <String, Object?>{'previousKind': 'data', 'nextKind': 'data'});
    expect(initialized.metadata, containsPair('controllerScope', 'sample-logging'));
    expect(initialized.error, isNull);
    expect(initialized.stackTrace, isNull);
  });

  test('failed async build logs the final AsyncError and stack trace', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(failingBuildProvider.future),
      throwsA(isA<StateError>().having((error) => error.message, 'message', 'restore failed')),
    );

    final initialized = logger.records.singleWhere((record) => record.phase == EventLogPhase.initialStateEstablished);
    expect(initialized.nextStateKind, AsyncValueKind.error);
    expect(initialized.nextStateLabel, isNull);
    expect(initialized.error, isA<StateError>().having((error) => error.message, 'message', 'restore failed'));
    expect(initialized.stackTrace, isNotNull);
  });

  test('synchronously thrown build logs the final AsyncError and stack trace', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(synchronousFailingBuildProvider.future),
      throwsA(isA<StateError>().having((error) => error.message, 'message', 'sync restore failed')),
    );

    final initialized = logger.records.singleWhere((record) => record.phase == EventLogPhase.initialStateEstablished);
    expect(initialized.nextStateKind, AsyncValueKind.error);
    expect(initialized.error, isA<StateError>().having((error) => error.message, 'message', 'sync restore failed'));
    expect(initialized.stackTrace, isNotNull);
  });

  test('retryable build logs terminal data instead of intermediate retry loading', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final terminalState = Completer<AsyncValue<int>>();
    final subscription = container.listen(retryThenSuccessProvider, (_, next) {
      if (next case AsyncData<int>()) {
        terminalState.complete(next);
      }
    }, fireImmediately: true);
    addTearDown(subscription.close);

    final settled = await terminalState.future.timeout(const Duration(seconds: 1));

    expect(container.read(retryThenSuccessProvider.notifier).attempts, 2);
    expect(settled.value, 42);
    final initialized = logger.records.singleWhere((record) => record.phase == EventLogPhase.initialStateEstablished);
    expect(initialized.nextStateKind, AsyncValueKind.data);
    expect(initialized.nextStateLabel, isNull);
    expect(initialized.error, isNull);
    expect(initialized.stackTrace, isNull);
  });

  test('retry exhaustion logs only the terminal AsyncError', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final terminalState = Completer<AsyncValue<int>>();
    final subscription = container.listen(retryExhaustionProvider, (_, next) {
      if (next case AsyncError<int>()) {
        terminalState.complete(next);
      }
    }, fireImmediately: true);
    addTearDown(subscription.close);

    final settled = await terminalState.future.timeout(const Duration(seconds: 1));

    expect(container.read(retryExhaustionProvider.notifier).attempts, 2);
    expect(settled.error, isA<Exception>().having((error) => error.toString(), 'message', 'Exception: retry failed 2'));
    final initialized = logger.records.singleWhere((record) => record.phase == EventLogPhase.initialStateEstablished);
    expect(initialized.nextStateKind, AsyncValueKind.error);
    expect(
      initialized.error,
      isA<Exception>().having((error) => error.toString(), 'message', 'Exception: retry failed 2'),
    );
    expect(initialized.stackTrace, isNotNull);
  });

  test('sync build logs initialization even when state summary hooks are not overridden', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    expect(await container.read(plainSyncProvider.future), 7);

    final initialized = logger.records.singleWhere((record) => record.phase == EventLogPhase.initialStateEstablished);
    expect(initialized.nextStateKind, AsyncValueKind.data);
    expect(initialized.nextStateLabel, isNull);
    expect(initialized.stateMetadata, isEmpty);
  });

  test('provider rebuild logs the first ref disposal without duplicating initialization', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);

    final notifier = container.read(rebuildingProvider.notifier);
    expect(await container.read(rebuildingProvider.future), 1);
    expect(logger.records.map((record) => record.phase), <EventLogPhase>[
      EventLogPhase.controllerCreated,
      EventLogPhase.initialStateEstablished,
    ]);

    container.invalidate(rebuildingProvider);

    expect(await container.read(rebuildingProvider.future), 2);
    expect(container.read(rebuildingProvider.notifier), same(notifier));
    expect(logger.records.where((record) => record.phase == EventLogPhase.initialStateEstablished), hasLength(1));
    expect(logger.records.map((record) => record.phase), <EventLogPhase>[
      EventLogPhase.controllerCreated,
      EventLogPhase.initialStateEstablished,
      EventLogPhase.controllerDisposed,
    ]);

    container.dispose();

    expect(logger.records.where((record) => record.phase == EventLogPhase.controllerDisposed), hasLength(1));
  });

  test('invalidating an in-flight build logs only the replacement terminal state', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    final notifier = container.read(cancellableBuildProvider.notifier);
    container.read(cancellableBuildProvider.future);
    expect(notifier.completions, hasLength(1));

    container.invalidate(cancellableBuildProvider);
    final replacement = container.read(cancellableBuildProvider.future);
    expect(container.read(cancellableBuildProvider.notifier), same(notifier));
    expect(notifier.completions, hasLength(2));

    notifier.completions.first.complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(logger.records.where((record) => record.phase == EventLogPhase.initialStateEstablished), isEmpty);

    notifier.completions.last.complete(2);
    expect(await replacement, 2);

    final initialized = logger.records.where((record) => record.phase == EventLogPhase.initialStateEstablished);
    expect(initialized, hasLength(1));
    expect(initialized.single.nextStateKind, AsyncValueKind.data);
  });

  test('dispatch logs before and after AsyncValue state kinds', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    final completed = logger.records.singleWhere((record) => record.phase == EventLogPhase.eventCompleted);
    expect(completed.controllerName, 'LoggingController');
    expect(completed.eventName, 'IncrementEvent');
    expect(completed.previousStateKind, AsyncValueKind.data);
    expect(completed.nextStateKind, AsyncValueKind.data);
    expect(completed.hasChanged, isTrue);
    expect(completed.metadata, containsPair('kind', 'increment'));
    expect(completed.metadata, containsPair('controllerScope', 'sample-logging'));
    expect(completed.error, isNull);
    expect(completed.stackTrace, isNull);
  });

  test('dispatch logs each state assignment as ordered transition records', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const MultiStepEvent());

    final eventRecords = logger.records.where((record) => record.eventName == 'MultiStepEvent').toList();
    expect(eventRecords.map((record) => record.phase), <EventLogPhase>[
      EventLogPhase.eventStarted,
      EventLogPhase.transition,
      EventLogPhase.transition,
      EventLogPhase.transition,
      EventLogPhase.eventCompleted,
    ]);

    final transitions = eventRecords.where((record) => record.phase == EventLogPhase.transition).toList();
    expect(transitions.map((record) => record.transitionIndex), <int>[1, 2, 3]);
    expect(transitions.map((record) => record.previousStateKind), <AsyncValueKind>[
      AsyncValueKind.data,
      AsyncValueKind.data,
      AsyncValueKind.loading,
    ]);
    expect(transitions.map((record) => record.nextStateKind), <AsyncValueKind>[
      AsyncValueKind.data,
      AsyncValueKind.loading,
      AsyncValueKind.data,
    ]);
    expect(transitions.first.previousStateLabel, 'value:0');
    expect(transitions.first.nextStateLabel, 'value:1');
    expect(transitions.first.stateMetadata, containsPair('previousKind', 'data'));
    expect(transitions.first.stateMetadata, containsPair('nextKind', 'data'));

    final completed = eventRecords.last;
    expect(completed.previousStateKind, AsyncValueKind.data);
    expect(completed.nextStateKind, AsyncValueKind.data);
    expect(completed.hasChanged, isTrue);
    expect(completed.duration, isNotNull);
    expect(eventRecords.map((record) => record.startedAt).toSet(), hasLength(1));
  });

  test('framework lifecycle and dispatch records carry occurrence data and increasing sequences', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());
    container.dispose();

    expect(
      logger.records.map((record) => record.phase),
      containsAll(<EventLogPhase>[
        EventLogPhase.controllerCreated,
        EventLogPhase.initialStateEstablished,
        EventLogPhase.eventStarted,
        EventLogPhase.transition,
        EventLogPhase.eventCompleted,
        EventLogPhase.controllerDisposed,
      ]),
    );
    expect(
      logger.records,
      everyElement(isA<EventLogRecord>().having((record) => record.occurredAt.isUtc, 'UTC', isTrue)),
    );
    expect(
      logger.records,
      everyElement(isA<EventLogRecord>().having((record) => record.recordSequence, 'recordSequence', isNotNull)),
    );
    final sequences = logger.records.map((record) => record.recordSequence!).toList();
    expect(sequences, orderedEquals(sequences.toList()..sort()));
    expect(sequences.toSet(), hasLength(sequences.length));
  });

  test('interleaved dispatches across containers are reconstructable by isolate-wide sequence', () async {
    final logger = CollectingEventLogger();
    final firstContainer = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    final secondContainer = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(firstContainer.dispose);
    addTearDown(secondContainer.dispose);
    final firstController = firstContainer.read(loggingProvider.notifier);
    final secondController = secondContainer.read(loggingProvider.notifier);
    await Future.wait(<Future<int>>[
      firstContainer.read(loggingProvider.future),
      secondContainer.read(loggingProvider.future),
    ]);
    final firstEntered = Completer<void>();
    final firstReleaseTransition = Completer<void>();
    final firstTransitioned = Completer<void>();
    final firstReleaseCompletion = Completer<void>();
    final secondEntered = Completer<void>();
    final secondReleaseTransition = Completer<void>();
    final secondTransitioned = Completer<void>();
    final secondReleaseCompletion = Completer<void>();

    final firstDispatch = firstController.dispatch(
      GatedPhaseEvent(
        name: 'first',
        entered: firstEntered,
        releaseTransition: firstReleaseTransition.future,
        transitioned: firstTransitioned,
        releaseCompletion: firstReleaseCompletion.future,
        value: 1,
      ),
    );
    await firstEntered.future;
    final secondDispatch = secondController.dispatch(
      GatedPhaseEvent(
        name: 'second',
        entered: secondEntered,
        releaseTransition: secondReleaseTransition.future,
        transitioned: secondTransitioned,
        releaseCompletion: secondReleaseCompletion.future,
        value: 2,
      ),
    );
    await secondEntered.future;
    firstReleaseTransition.complete();
    await firstTransitioned.future;
    secondReleaseTransition.complete();
    await secondTransitioned.future;
    secondReleaseCompletion.complete();
    await secondDispatch;
    firstReleaseCompletion.complete();
    await firstDispatch;

    final dispatchRecords = logger.records.where((record) => record.eventName == 'GatedPhaseEvent').toList();
    final orderedBySequence = dispatchRecords.toList()
      ..sort((left, right) => left.recordSequence!.compareTo(right.recordSequence!));
    expect(orderedBySequence, orderedEquals(dispatchRecords));
    expect(orderedBySequence.map((record) => '${record.metadata['name']}:${record.phase.name}'), <String>[
      'first:eventStarted',
      'second:eventStarted',
      'first:transition',
      'second:transition',
      'second:eventCompleted',
      'first:eventCompleted',
    ]);

    for (final name in <String>['first', 'second']) {
      final spanRecords = dispatchRecords.where((record) => record.metadata['name'] == name).toList();
      expect(spanRecords.map((record) => record.startedAt).toSet(), hasLength(1));
      expect(
        spanRecords.map((record) => record.occurredAt),
        orderedEquals(spanRecords.map((record) => record.occurredAt).toList()..sort()),
      );
      final spanSequences = spanRecords.map((record) => record.recordSequence!).toList();
      expect(spanSequences, orderedEquals(spanSequences.toList()..sort()));
    }

    final allSequences = logger.records.map((record) => record.recordSequence!).toList();
    expect(allSequences, orderedEquals(allSequences.toList()..sort()));
    expect(allSequences.toSet(), hasLength(allSequences.length));
  });

  test('terminal duration covers controlled handler wait and is non-negative', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final entered = Completer<void>();
    final releaseTransition = Completer<void>();
    final transitioned = Completer<void>();
    final releaseCompletion = Completer<void>();

    final dispatch = container
        .read(loggingProvider.notifier)
        .dispatch(
          GatedPhaseEvent(
            name: 'duration',
            entered: entered,
            releaseTransition: releaseTransition.future,
            transitioned: transitioned,
            releaseCompletion: releaseCompletion.future,
            value: 3,
          ),
        );
    await entered.future;
    final controlledWait = Stopwatch()..start();
    releaseTransition.complete();
    await transitioned.future;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    controlledWait.stop();
    releaseCompletion.complete();
    await dispatch;

    final completed = logger.records.singleWhere(
      (record) => record.eventName == 'GatedPhaseEvent' && record.phase == EventLogPhase.eventCompleted,
    );
    expect(completed.duration, isNotNull);
    expect(completed.duration!.isNegative, isFalse);
    expect(completed.duration, greaterThanOrEqualTo(controlledWait.elapsed));
  });

  test('failed dispatch records terminal occurrence, sequence, elapsed duration, and original stack', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final entered = Completer<void>();
    final release = Completer<void>();
    final originalError = StateError('gated failure');
    Object? caughtError;
    StackTrace? caughtStackTrace;

    final dispatch = container
        .read(loggingProvider.notifier)
        .dispatch(GatedFailureEvent(entered: entered, release: release.future, error: originalError));
    await entered.future;
    final controlledWait = Stopwatch()..start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    controlledWait.stop();
    release.complete();
    try {
      await dispatch;
    } catch (error, stackTrace) {
      caughtError = error;
      caughtStackTrace = stackTrace;
    }

    final records = logger.records.where((record) => record.eventName == 'GatedFailureEvent').toList();
    final failed = records.singleWhere((record) => record.phase == EventLogPhase.eventFailed);
    expect(caughtError, same(originalError));
    expect(failed.error, same(originalError));
    expect(failed.stackTrace.toString(), caughtStackTrace.toString());
    expect(failed.occurredAt.isUtc, isTrue);
    expect(failed.recordSequence, isNotNull);
    expect(failed.duration, isNotNull);
    expect(failed.duration!.isNegative, isFalse);
    expect(failed.duration, greaterThanOrEqualTo(controlledWait.elapsed));
    expect(
      records.map((record) => record.recordSequence!),
      orderedEquals(records.map((record) => record.recordSequence!).toList()..sort()),
    );
  });

  test('logs controller lifecycle without event payloads', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);

    await container.read(loggingProvider.future);
    container.dispose();

    final lifecyclePhases = logger.records
        .where(
          (record) =>
              record.phase == EventLogPhase.controllerCreated || record.phase == EventLogPhase.controllerDisposed,
        )
        .map((record) => record.phase)
        .toList();
    expect(lifecyclePhases, <EventLogPhase>[EventLogPhase.controllerCreated, EventLogPhase.controllerDisposed]);
    final created = logger.records.where((record) => record.phase == EventLogPhase.controllerCreated).single;
    final disposed = logger.records.where((record) => record.phase == EventLogPhase.controllerDisposed).single;
    expect(created.eventName, isNull);
    expect(disposed.eventName, isNull);
    expect(created.metadata, containsPair('controllerScope', 'sample-logging'));
    expect(disposed.metadata, containsPair('controllerScope', 'sample-logging'));
  });

  test('lifecycle logger failures do not break provider creation or disposal', () async {
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(ThrowingEventLogger())]);

    await container.read(loggingProvider.future);

    expect(container.dispose, returnsNormally);
  });

  test('concurrent dispatches keep transition attribution in their async zones', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await Future.wait(<Future<void>>[
      container.read(loggingProvider.notifier).dispatch(const ConcurrentFirstEvent()),
      container.read(loggingProvider.notifier).dispatch(const ConcurrentSecondEvent()),
    ]);

    final firstTransitions = logger.records
        .where((record) => record.phase == EventLogPhase.transition && record.eventName == 'ConcurrentFirstEvent')
        .toList();
    final secondTransitions = logger.records
        .where((record) => record.phase == EventLogPhase.transition && record.eventName == 'ConcurrentSecondEvent')
        .toList();

    expect(firstTransitions, hasLength(1));
    expect(secondTransitions, hasLength(1));
    expect(firstTransitions.single.transitionIndex, 1);
    expect(secondTransitions.single.transitionIndex, 1);
    expect(firstTransitions.single.metadata, containsPair('kind', 'concurrent-first'));
    expect(secondTransitions.single.metadata, containsPair('kind', 'concurrent-second'));
    expect(firstTransitions.single.traceContext.traceId, isNot(secondTransitions.single.traceContext.traceId));
  });

  test('concurrent dispatch terminal records keep each event owned outcome', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await Future.wait(<Future<void>>[
      container.read(loggingProvider.notifier).dispatch(const ConcurrentFirstEvent()),
      container.read(loggingProvider.notifier).dispatch(const ConcurrentSecondEvent()),
    ]);

    final firstCompleted = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'ConcurrentFirstEvent',
    );
    final secondCompleted = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'ConcurrentSecondEvent',
    );
    expect(firstCompleted.nextStateLabel, 'value:100');
    expect(secondCompleted.nextStateLabel, 'value:200');
  });

  test('dispatch without owned writes completes with its admission state', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controller = container.read(loggingProvider.notifier);
    final entered = Completer<void>();
    final release = Completer<void>();

    final dispatch = controller.dispatch(NoWriteEvent(entered: entered, release: release.future));
    await entered.future;
    controller.setDirectly(41);
    release.complete();
    await dispatch;

    final completed = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'NoWriteEvent',
    );
    expect(completed.previousStateLabel, 'value:0');
    expect(completed.nextStateLabel, 'value:0');
    expect(completed.hasChanged, isFalse);
    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 41));
  });

  test('awaited same-controller child outcome folds into its active parent', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controller = container.read(loggingProvider.notifier);
    final childSettled = Completer<void>();
    final release = Completer<void>();

    final dispatch = controller.dispatch(
      ParentWithoutLaterWriteEvent(childSettled: childSettled, release: release.future),
    );
    await childSettled.future;
    controller.setDirectly(90);
    release.complete();
    await dispatch;

    final parent = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'ParentWithoutLaterWriteEvent',
    );
    final child = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'ChildEvent',
    );
    expect(child.nextStateLabel, 'value:5');
    expect(parent.nextStateLabel, 'value:5');
    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 90));
  });

  test('parent write after awaited child overrides the folded child outcome', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controller = container.read(loggingProvider.notifier);
    final wrote = Completer<void>();
    final release = Completer<void>();

    final dispatch = controller.dispatch(ParentWriteAfterChildEvent(wrote: wrote, release: release.future));
    await wrote.future;
    controller.setDirectly(90);
    release.complete();
    await dispatch;

    final parent = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'ParentWriteAfterChildEvent',
    );
    expect(parent.nextStateLabel, 'value:10');
    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 90));
  });

  test('older child finishing after a newer parent write cannot overwrite the parent outcome', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controller = container.read(loggingProvider.notifier);
    final childWrote = Completer<void>();
    final parentWrote = Completer<void>();
    final releaseChild = Completer<void>();

    final dispatch = controller.dispatch(
      ParentWritesWhileChildPendingEvent(
        childWrote: childWrote,
        parentWrote: parentWrote,
        releaseChild: releaseChild.future,
      ),
    );
    await parentWrote.future;
    releaseChild.complete();
    await dispatch;

    final parent = logger.records.singleWhere(
      (record) =>
          record.phase == EventLogPhase.eventCompleted && record.eventName == 'ParentWritesWhileChildPendingEvent',
    );
    expect(parent.nextStateLabel, 'value:2');
  });

  test('children completing in reverse preserve their state write order in the parent outcome', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controller = container.read(loggingProvider.notifier);
    final firstWrote = Completer<void>();
    final secondWrote = Completer<void>();
    final releaseFirst = Completer<void>();
    final releaseSecond = Completer<void>();
    final secondCompleted = Completer<void>();

    final dispatch = controller.dispatch(
      ReverseCompletionChildrenEvent(
        firstWrote: firstWrote,
        secondWrote: secondWrote,
        releaseFirst: releaseFirst.future,
        releaseSecond: releaseSecond.future,
        secondCompleted: secondCompleted,
      ),
    );
    await secondWrote.future;
    releaseSecond.complete();
    await secondCompleted.future;
    releaseFirst.complete();
    await dispatch;

    final parent = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'ReverseCompletionChildrenEvent',
    );
    expect(parent.nextStateLabel, 'value:2');
  });

  test('cross-controller child outcome does not fold into its parent', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final parentController = container.read(loggingProvider.notifier);
    final childController = container.read(otherLoggingProvider.notifier);
    await Future.wait(<Future<int>>[
      container.read(loggingProvider.future),
      container.read(otherLoggingProvider.future),
    ]);

    await parentController.dispatch(CrossControllerParentEvent(() => childController.dispatch(const ChildEvent())));

    final parent = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'CrossControllerParentEvent',
    );
    final child = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'ChildEvent',
    );
    expect(parent.nextStateLabel, 'value:0');
    expect(child.nextStateLabel, 'value:5');
  });

  test('same-controller child finishing after parent closes is not folded', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controller = container.read(loggingProvider.notifier);
    final childStarted = Completer<void>();
    final releaseChild = Completer<void>();
    final childCompleted = Completer<void>();

    await controller.dispatch(
      FireAndForgetParentEvent(
        childStarted: childStarted,
        releaseChild: releaseChild.future,
        childCompleted: childCompleted,
      ),
    );
    releaseChild.complete();
    await childCompleted.future;

    final parent = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'FireAndForgetParentEvent',
    );
    final child = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'DelayedChildEvent',
    );
    expect(parent.nextStateLabel, 'value:0');
    expect(child.nextStateLabel, 'value:70');
  });

  test('transition logger observes the already committed next state', () async {
    late ProviderContainer container;
    final observedValues = <int>[];
    final logger = CallbackEventLogger((record) {
      if (record.phase == EventLogPhase.transition && record.eventName == 'IncrementEvent') {
        final current = container.read(loggingProvider);
        if (current case AsyncData<int>(:final value)) {
          observedValues.add(value);
        }
      }
    });
    container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    expect(observedValues, <int>[1]);
  });

  test('failed state assignment keeps its last successful outcome and isolates later dispatches', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controller = container.read(rejectingStateProvider.notifier);

    await expectLater(controller.dispatch(const RejectingStateEvent(1)), throwsA(same(controller.rejection)));

    final failedRecords = logger.records.where((record) => record.eventName == 'RejectingStateEvent').toList();
    expect(failedRecords.map((record) => record.phase), <EventLogPhase>[
      EventLogPhase.eventStarted,
      EventLogPhase.eventFailed,
    ]);
    final failed = failedRecords.last;
    expect(failed.previousStateLabel, 'value:0');
    expect(failed.nextStateLabel, 'value:0');
    expect(failed.hasChanged, isFalse);
    expect(failed.error, same(controller.rejection));
    expect(failed.stackTrace, isNotNull);
    expect(container.read(rejectingStateProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 1));

    await controller.dispatch(const RejectingStateEvent(2));

    final recoveryRecords = logger.records.where((record) => record.eventName == 'RecoveryStateEvent').toList();
    expect(recoveryRecords.map((record) => record.phase), <EventLogPhase>[
      EventLogPhase.eventStarted,
      EventLogPhase.transition,
      EventLogPhase.eventCompleted,
    ]);
    final recovery = recoveryRecords.last;
    expect(recovery.previousStateLabel, 'value:1');
    expect(recovery.nextStateLabel, 'value:2');
    expect(recovery.error, isNull);
    expect(container.read(rejectingStateProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 2));
  });

  test('state writes are attributed only to their owning controller instance', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controllerA = container.read(loggingProvider.notifier);
    final controllerB = container.read(otherLoggingProvider.notifier);
    await Future.wait(<Future<int>>[
      container.read(loggingProvider.future),
      container.read(otherLoggingProvider.future),
    ]);

    await controllerA.dispatch(DirectWriteEvent(() => controllerB.setDirectly(77)));

    expect(container.read(otherLoggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 77));
    expect(
      logger.records.where(
        (record) => record.phase == EventLogPhase.transition && record.eventName == 'DirectWriteEvent',
      ),
      isEmpty,
    );
  });

  test('state writes inherited after dispatch closes are not attributed', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final trigger = Completer<void>();
    final completed = Completer<void>();

    await container
        .read(loggingProvider.notifier)
        .dispatch(InheritedWriteEvent(trigger: trigger.future, completed: completed));
    trigger.complete();
    await completed.future;

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 88));
    expect(
      logger.records.where(
        (record) => record.phase == EventLogPhase.transition && record.eventName == 'InheritedWriteEvent',
      ),
      isEmpty,
    );
  });

  test('state summary failures do not break transitions', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const ThrowStateSummaryEvent());

    final transition = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.transition && record.eventName == 'ThrowStateSummaryEvent',
    );
    expect(transition.previousStateLabel, 'value:0');
    expect(transition.nextStateLabel, isNull);
    expect(transition.stateMetadata, isEmpty);
    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 404));
  });

  test('dispatch logs thrown errors and preserves the original stack trace', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(loggingProvider.notifier).dispatch(const ThrowEvent()),
      throwsA(isA<StateError>()),
    );

    final failed = logger.records.singleWhere((record) => record.phase == EventLogPhase.eventFailed);
    expect(failed.eventName, 'ThrowEvent');
    expect(failed.error, isA<StateError>());
    expect(failed.stackTrace, isNotNull);
  });

  test('event failure logs final state after transitions', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(loggingProvider.notifier).dispatch(const ThrowAfterStateEvent()),
      throwsA(isA<StateError>().having((error) => error.message, 'message', 'state changed then failed')),
    );

    final eventRecords = logger.records.where((record) => record.eventName == 'ThrowAfterStateEvent').toList();
    expect(eventRecords.map((record) => record.phase), <EventLogPhase>[
      EventLogPhase.eventStarted,
      EventLogPhase.transition,
      EventLogPhase.eventFailed,
    ]);

    final failed = eventRecords.singleWhere((record) => record.phase == EventLogPhase.eventFailed);
    expect(failed.previousStateKind, AsyncValueKind.data);
    expect(failed.nextStateKind, AsyncValueKind.data);
    expect(failed.hasChanged, isTrue);
    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 30));
  });

  test('failed dispatch keeps its owned outcome and original error stack', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controller = container.read(loggingProvider.notifier);
    final afterWrite = Completer<void>();
    final release = Completer<void>();
    final originalError = StateError('owned outcome failed');
    Object? caughtError;
    StackTrace? caughtStackTrace;

    final dispatch = controller.dispatch(
      ThrowOwnedOutcomeEvent(afterWrite: afterWrite, release: release.future, error: originalError),
    );
    await afterWrite.future;
    controller.setDirectly(200);
    release.complete();
    try {
      await dispatch;
    } catch (error, stackTrace) {
      caughtError = error;
      caughtStackTrace = stackTrace;
    }

    final failed = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventFailed && record.eventName == 'ThrowOwnedOutcomeEvent',
    );
    expect(caughtError, same(originalError));
    expect(failed.error, same(originalError));
    expect(failed.stackTrace.toString(), caughtStackTrace.toString());
    expect(failed.previousStateLabel, 'value:0');
    expect(failed.nextStateLabel, 'value:30');
    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 200));
  });

  test('inherited work after failed dispatch closes cannot add a transition', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final trigger = Completer<void>();
    final completed = Completer<void>();
    final originalError = StateError('failed before inherited write');

    await expectLater(
      container
          .read(loggingProvider.notifier)
          .dispatch(InheritedWriteThenThrowEvent(trigger: trigger.future, completed: completed, error: originalError)),
      throwsA(same(originalError)),
    );
    trigger.complete();
    await completed.future;

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 88));
    expect(
      logger.records.where(
        (record) => record.phase == EventLogPhase.transition && record.eventName == 'InheritedWriteThenThrowEvent',
      ),
      isEmpty,
    );
  });

  test('nested dispatches keep one trace id and create child spans', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const ParentEvent());

    final parent = logger.records.singleWhere(
      (record) => record.eventName == 'ParentEvent' && record.phase == EventLogPhase.eventCompleted,
    );
    final child = logger.records.singleWhere(
      (record) => record.eventName == 'ChildEvent' && record.phase == EventLogPhase.eventCompleted,
    );

    expect(child.traceContext.traceId, parent.traceContext.traceId);
    expect(parent.traceContext.traceId, startsWith('trace-'));
    expect(parent.traceContext.spanId, startsWith('span-'));
    expect(child.traceContext.spanId, startsWith('span-'));
    expect(parent.traceContext.parentSpanId, isNull);
    expect(child.traceContext.parentSpanId, parent.traceContext.spanId);
    expect(child.traceContext.spanId, isNot(parent.traceContext.spanId));
  });

  test('dispatch inherited from a closed dispatch zone starts a root trace', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final controller = container.read(loggingProvider.notifier);
    final trigger = Completer<void>();
    final completed = Completer<void>();

    await controller.dispatch(
      InheritedDispatchEvent(
        trigger: trigger.future,
        dispatch: () => controller.dispatch(const IncrementEvent()),
        completed: completed,
      ),
    );
    trigger.complete();
    await completed.future;

    final staleParent = logger.records.singleWhere(
      (record) => record.eventName == 'InheritedDispatchEvent' && record.phase == EventLogPhase.eventCompleted,
    );
    final laterDispatch = logger.records.singleWhere(
      (record) => record.eventName == 'IncrementEvent' && record.phase == EventLogPhase.eventCompleted,
    );
    expect(laterDispatch.traceContext.traceId, isNot(staleParent.traceContext.traceId));
    expect(laterDispatch.traceContext.parentSpanId, isNull);
  });

  test('dispatch inside an explicit trace context creates a child span', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final explicitParent = TraceContext.root(startedAt: DateTime.utc(2026, 7, 31));

    await TraceContext.run(
      explicitParent,
      () => container.read(loggingProvider.notifier).dispatch(const IncrementEvent()),
    );

    final child = logger.records.singleWhere(
      (record) => record.eventName == 'IncrementEvent' && record.phase == EventLogPhase.eventCompleted,
    );
    expect(child.traceContext.traceId, explicitParent.traceId);
    expect(child.traceContext.parentSpanId, explicitParent.spanId);
  });

  test('metadata failures do not break successful dispatches', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const ThrowMetadataEvent());

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 20));
  });

  test('metadata failures do not mask original event handler errors', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(loggingProvider.notifier).dispatch(const ThrowEventAndMetadataEvent()),
      throwsA(isA<StateError>().having((error) => error.message, 'message', 'handler failed')),
    );

    final failed = logger.records.singleWhere((record) => record.phase == EventLogPhase.eventFailed);
    expect(failed.eventName, 'ThrowEventAndMetadataEvent');
    expect(failed.error, isA<StateError>().having((error) => error.message, 'message', 'handler failed'));
    expect(failed.stackTrace, isNotNull);
    expect(failed.metadata, containsPair('controllerScope', 'sample-logging'));
    expect(failed.metadata, isNot(contains('kind')));
  });

  test('logger failures do not break application flow', () async {
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(ThrowingEventLogger())]);
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 1));
  });

  test('hasChanged does not invoke AsyncData payload equality', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(explodingEqualityProvider.notifier).dispatch(const ExplodingEqualityEvent());

    final completed = logger.records.singleWhere((record) => record.phase == EventLogPhase.eventCompleted);
    expect(completed.hasChanged, isTrue);
  });

  test('EventLogRecord snapshots metadata maps', () {
    final metadata = <String, Object?>{'kind': 'original'};
    final stateMetadata = <String, Object?>{'state': 'ready'};
    final record = EventLogRecord(
      phase: EventLogPhase.transition,
      traceContext: TraceContext.root(startedAt: DateTime.utc(2026, 6)),
      controllerName: 'LoggingController',
      eventName: 'IncrementEvent',
      startedAt: DateTime.utc(2026, 6),
      metadata: metadata,
      stateMetadata: stateMetadata,
    );

    metadata['kind'] = 'mutated';
    stateMetadata['state'] = 'mutated';

    expect(record.metadata, containsPair('kind', 'original'));
    expect(record.stateMetadata, containsPair('state', 'ready'));
    expect(() => record.metadata['kind'] = 'changed', throwsUnsupportedError);
    expect(() => record.stateMetadata['state'] = 'changed', throwsUnsupportedError);
  });

  test('EventLogRecord defaults occurredAt to startedAt', () {
    final startedAt = DateTime.utc(2026, 7, 31, 9);
    final record = EventLogRecord(
      phase: EventLogPhase.eventStarted,
      traceContext: TraceContext.root(startedAt: startedAt),
      controllerName: 'LoggingController',
      startedAt: startedAt,
    );

    expect(record.occurredAt, startedAt);
    expect(record.recordSequence, isNull);
  });

  test('EventLogRecord preserves an explicit occurredAt', () {
    final startedAt = DateTime.utc(2026, 7, 31, 9);
    final occurredAt = startedAt.add(const Duration(milliseconds: 25));
    final record = EventLogRecord(
      phase: EventLogPhase.eventCompleted,
      traceContext: TraceContext.root(startedAt: startedAt),
      controllerName: 'LoggingController',
      startedAt: startedAt,
      occurredAt: occurredAt,
    );

    expect(record.startedAt, startedAt);
    expect(record.occurredAt, occurredAt);
  });

  test('EventLogRecord preserves an explicit recordSequence', () {
    final startedAt = DateTime.utc(2026, 7, 31, 9);
    final record = EventLogRecord(
      phase: EventLogPhase.eventCompleted,
      traceContext: TraceContext.root(startedAt: startedAt),
      controllerName: 'LoggingController',
      startedAt: startedAt,
      recordSequence: 42,
    );

    expect(record.recordSequence, 42);
  });

  test('TraceContext.run exposes current context only inside the async zone', () async {
    final context = TraceContext.root(startedAt: DateTime.utc(2026, 6));

    expect(TraceContext.current, isNull);
    await TraceContext.run(context, () async {
      await Future<void>.delayed(Duration.zero);
      expect(TraceContext.current, same(context));
    });
    expect(TraceContext.current, isNull);
  });

  test('EventDispatchContext.run exposes current context inside the async zone', () async {
    final owner = Object();
    final traceContext = TraceContext.root(startedAt: DateTime.utc(2026, 6));
    final dispatchContext = EventDispatchContext(
      owner: owner,
      traceContext: traceContext,
      controllerName: 'LoggingController',
      eventName: 'IncrementEvent',
      startedAt: traceContext.startedAt,
    );

    expect(EventDispatchContext.current, isNull);
    expect(EventDispatchContext.hasAmbientContext, isFalse);
    await EventDispatchContext.run(dispatchContext, () async {
      await Future<void>.delayed(Duration.zero);
      expect(TraceContext.current, same(traceContext));
      expect(EventDispatchContext.current, same(dispatchContext));
      expect(EventDispatchContext.currentFor(owner), same(dispatchContext));
      expect(EventDispatchContext.currentFor(Object()), isNull);
      expect(EventDispatchContext.hasAmbientContext, isTrue);
    });
    expect(EventDispatchContext.current, isNull);
    expect(EventDispatchContext.hasAmbientContext, isFalse);
  });

  test('EventDispatchContext ownership uses identity', () {
    final owner = _EqualOwner();
    final equalButDistinctOwner = _EqualOwner();
    final dispatchContext = EventDispatchContext(
      owner: owner,
      traceContext: TraceContext.root(startedAt: DateTime.utc(2026, 6)),
      controllerName: 'LoggingController',
      eventName: 'IncrementEvent',
      startedAt: DateTime.utc(2026, 6),
    );

    expect(dispatchContext.owns(owner), isTrue);
    expect(dispatchContext.owns(Object()), isFalse);
    expect(dispatchContext.owns(equalButDistinctOwner), isFalse);
  });

  test('closed EventDispatchContext is stale but no longer current', () async {
    final owner = Object();
    final dispatchContext = EventDispatchContext(
      owner: owner,
      traceContext: TraceContext.root(startedAt: DateTime.utc(2026, 6)),
      controllerName: 'LoggingController',
      eventName: 'IncrementEvent',
      startedAt: DateTime.utc(2026, 6),
    );

    await EventDispatchContext.run(dispatchContext, () async {
      expect(dispatchContext.isActive, isTrue);
      expect(EventDispatchContext.current, same(dispatchContext));

      dispatchContext.close();
      dispatchContext.close();

      expect(dispatchContext.isActive, isFalse);
      expect(EventDispatchContext.current, isNull);
      expect(EventDispatchContext.currentFor(owner), isNull);
      expect(EventDispatchContext.hasAmbientContext, isTrue);
    });
  });

  test('EventDispatchContext retains its parent context', () {
    final parent = EventDispatchContext(
      owner: Object(),
      traceContext: TraceContext.root(startedAt: DateTime.utc(2026, 6)),
      controllerName: 'LoggingController',
      eventName: 'ParentEvent',
      startedAt: DateTime.utc(2026, 6),
    );
    final child = EventDispatchContext(
      owner: Object(),
      parent: parent,
      traceContext: parent.traceContext.child(),
      controllerName: 'LoggingController',
      eventName: 'ChildEvent',
      startedAt: DateTime.utc(2026, 6),
    );

    expect(child.parent, same(parent));
  });

  test('EventDispatchContext snapshots metadata maps', () {
    final metadata = <String, Object?>{'kind': 'original'};
    final traceContext = TraceContext.root(startedAt: DateTime.utc(2026, 6));
    final dispatchContext = EventDispatchContext(
      owner: Object(),
      traceContext: traceContext,
      controllerName: 'LoggingController',
      eventName: 'IncrementEvent',
      startedAt: traceContext.startedAt,
      metadata: metadata,
    );

    metadata['kind'] = 'mutated';

    expect(dispatchContext.metadata, containsPair('kind', 'original'));
    expect(() => dispatchContext.metadata['kind'] = 'changed', throwsUnsupportedError);
  });
}
