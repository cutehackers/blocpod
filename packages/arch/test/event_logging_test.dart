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

final loggingProvider = AsyncNotifierProvider<LoggingController, int>(
  LoggingController.new,
);

final explodingEqualityProvider =
    AsyncNotifierProvider<ExplodingEqualityController, ExplodingEquality>(
      ExplodingEqualityController.new,
    );

final class LoggingController
    extends EventControllerNotifier<int, LoggingEvent> {
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
    }
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
  Map<String, Object?> stateMetadata({
    required AsyncValue<int> previous,
    required AsyncValue<int> next,
  }) {
    if (next case AsyncData<int>(value: 404)) {
      throw StateError('state metadata failed');
    }
    return <String, Object?>{
      'previousKind': asyncValueKindOf(previous).name,
      'nextKind': asyncValueKindOf(next).name,
    };
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

final class ExplodingEqualityController
    extends EventControllerNotifier<ExplodingEquality, ExplodingEqualityEvent> {
  @override
  Future<ExplodingEquality> build() async {
    return const ExplodingEquality(0);
  }

  @override
  Future<void> onEvent(ExplodingEqualityEvent event) async {
    state = const AsyncData(ExplodingEquality(1));
  }

  @override
  bool updateShouldNotify(
    AsyncValue<ExplodingEquality> previous,
    AsyncValue<ExplodingEquality> next,
  ) {
    return !identical(previous, next);
  }
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

void main() {
  test('default logger is no-op and dispatch still succeeds', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(loggingProvider.notifier)
        .dispatch(const IncrementEvent());

    expect(
      container.read(loggingProvider),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 1),
    );
  });

  test('dispatch logs before and after AsyncValue state kinds', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(logger)],
    );
    addTearDown(container.dispose);

    await container
        .read(loggingProvider.notifier)
        .dispatch(const IncrementEvent());

    final completed = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted,
    );
    expect(completed.controllerName, 'LoggingController');
    expect(completed.eventName, 'IncrementEvent');
    expect(completed.previousStateKind, AsyncValueKind.data);
    expect(completed.nextStateKind, AsyncValueKind.data);
    expect(completed.hasChanged, isTrue);
    expect(completed.metadata, containsPair('kind', 'increment'));
    expect(
      completed.metadata,
      containsPair('controllerScope', 'sample-logging'),
    );
    expect(completed.error, isNull);
    expect(completed.stackTrace, isNull);
  });

  test(
    'dispatch logs each state assignment as ordered transition records',
    () async {
      final logger = CollectingEventLogger();
      final container = ProviderContainer(
        overrides: [eventLoggerProvider.overrideWithValue(logger)],
      );
      addTearDown(container.dispose);

      await container
          .read(loggingProvider.notifier)
          .dispatch(const MultiStepEvent());

      final eventRecords = logger.records
          .where((record) => record.eventName == 'MultiStepEvent')
          .toList();
      expect(eventRecords.map((record) => record.phase), <EventLogPhase>[
        EventLogPhase.eventStarted,
        EventLogPhase.transition,
        EventLogPhase.transition,
        EventLogPhase.transition,
        EventLogPhase.eventCompleted,
      ]);

      final transitions = eventRecords
          .where((record) => record.phase == EventLogPhase.transition)
          .toList();
      expect(transitions.map((record) => record.transitionIndex), <int>[
        1,
        2,
        3,
      ]);
      expect(
        transitions.map((record) => record.previousStateKind),
        <AsyncValueKind>[
          AsyncValueKind.data,
          AsyncValueKind.data,
          AsyncValueKind.loading,
        ],
      );
      expect(
        transitions.map((record) => record.nextStateKind),
        <AsyncValueKind>[
          AsyncValueKind.data,
          AsyncValueKind.loading,
          AsyncValueKind.data,
        ],
      );
      expect(transitions.first.previousStateLabel, 'value:0');
      expect(transitions.first.nextStateLabel, 'value:1');
      expect(
        transitions.first.stateMetadata,
        containsPair('previousKind', 'data'),
      );
      expect(transitions.first.stateMetadata, containsPair('nextKind', 'data'));

      final completed = eventRecords.last;
      expect(completed.previousStateKind, AsyncValueKind.data);
      expect(completed.nextStateKind, AsyncValueKind.data);
      expect(completed.hasChanged, isTrue);
      expect(completed.duration, isNotNull);
    },
  );

  test('logs controller lifecycle without event payloads', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(logger)],
    );

    await container.read(loggingProvider.future);
    container.dispose();

    final lifecyclePhases = logger.records
        .where(
          (record) =>
              record.phase == EventLogPhase.controllerCreated ||
              record.phase == EventLogPhase.controllerDisposed,
        )
        .map((record) => record.phase)
        .toList();
    expect(lifecyclePhases, <EventLogPhase>[
      EventLogPhase.controllerCreated,
      EventLogPhase.controllerDisposed,
    ]);
    final created = logger.records
        .where((record) => record.phase == EventLogPhase.controllerCreated)
        .single;
    final disposed = logger.records
        .where((record) => record.phase == EventLogPhase.controllerDisposed)
        .single;
    expect(created.eventName, isNull);
    expect(disposed.eventName, isNull);
    expect(created.metadata, containsPair('controllerScope', 'sample-logging'));
    expect(
      disposed.metadata,
      containsPair('controllerScope', 'sample-logging'),
    );
  });

  test(
    'lifecycle logger failures do not break provider creation or disposal',
    () async {
      final container = ProviderContainer(
        overrides: [
          eventLoggerProvider.overrideWithValue(ThrowingEventLogger()),
        ],
      );

      await container.read(loggingProvider.future);

      expect(container.dispose, returnsNormally);
    },
  );

  test(
    'concurrent dispatches keep transition attribution in their async zones',
    () async {
      final logger = CollectingEventLogger();
      final container = ProviderContainer(
        overrides: [eventLoggerProvider.overrideWithValue(logger)],
      );
      addTearDown(container.dispose);

      await Future.wait(<Future<void>>[
        container
            .read(loggingProvider.notifier)
            .dispatch(const ConcurrentFirstEvent()),
        container
            .read(loggingProvider.notifier)
            .dispatch(const ConcurrentSecondEvent()),
      ]);

      final firstTransitions = logger.records
          .where(
            (record) =>
                record.phase == EventLogPhase.transition &&
                record.eventName == 'ConcurrentFirstEvent',
          )
          .toList();
      final secondTransitions = logger.records
          .where(
            (record) =>
                record.phase == EventLogPhase.transition &&
                record.eventName == 'ConcurrentSecondEvent',
          )
          .toList();

      expect(firstTransitions, hasLength(1));
      expect(secondTransitions, hasLength(1));
      expect(firstTransitions.single.transitionIndex, 1);
      expect(secondTransitions.single.transitionIndex, 1);
      expect(
        firstTransitions.single.metadata,
        containsPair('kind', 'concurrent-first'),
      );
      expect(
        secondTransitions.single.metadata,
        containsPair('kind', 'concurrent-second'),
      );
      expect(
        firstTransitions.single.traceContext.traceId,
        isNot(secondTransitions.single.traceContext.traceId),
      );
    },
  );

  test('state summary failures do not break transitions', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(logger)],
    );
    addTearDown(container.dispose);

    await container
        .read(loggingProvider.notifier)
        .dispatch(const ThrowStateSummaryEvent());

    final transition = logger.records.singleWhere(
      (record) =>
          record.phase == EventLogPhase.transition &&
          record.eventName == 'ThrowStateSummaryEvent',
    );
    expect(transition.previousStateLabel, 'value:0');
    expect(transition.nextStateLabel, isNull);
    expect(transition.stateMetadata, isEmpty);
    expect(
      container.read(loggingProvider),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 404),
    );
  });

  test(
    'dispatch logs thrown errors and preserves the original stack trace',
    () async {
      final logger = CollectingEventLogger();
      final container = ProviderContainer(
        overrides: [eventLoggerProvider.overrideWithValue(logger)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(loggingProvider.notifier).dispatch(const ThrowEvent()),
        throwsA(isA<StateError>()),
      );

      final failed = logger.records.singleWhere(
        (record) => record.phase == EventLogPhase.eventFailed,
      );
      expect(failed.eventName, 'ThrowEvent');
      expect(failed.error, isA<StateError>());
      expect(failed.stackTrace, isNotNull);
    },
  );

  test('event failure logs final state after transitions', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(logger)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(loggingProvider.notifier)
          .dispatch(const ThrowAfterStateEvent()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'state changed then failed',
        ),
      ),
    );

    final eventRecords = logger.records
        .where((record) => record.eventName == 'ThrowAfterStateEvent')
        .toList();
    expect(eventRecords.map((record) => record.phase), <EventLogPhase>[
      EventLogPhase.eventStarted,
      EventLogPhase.transition,
      EventLogPhase.eventFailed,
    ]);

    final failed = eventRecords.singleWhere(
      (record) => record.phase == EventLogPhase.eventFailed,
    );
    expect(failed.previousStateKind, AsyncValueKind.data);
    expect(failed.nextStateKind, AsyncValueKind.data);
    expect(failed.hasChanged, isTrue);
    expect(
      container.read(loggingProvider),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 30),
    );
  });

  test('nested dispatches keep one trace id and create child spans', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(logger)],
    );
    addTearDown(container.dispose);

    await container
        .read(loggingProvider.notifier)
        .dispatch(const ParentEvent());

    final parent = logger.records.singleWhere(
      (record) =>
          record.eventName == 'ParentEvent' &&
          record.phase == EventLogPhase.eventCompleted,
    );
    final child = logger.records.singleWhere(
      (record) =>
          record.eventName == 'ChildEvent' &&
          record.phase == EventLogPhase.eventCompleted,
    );

    expect(child.traceContext.traceId, parent.traceContext.traceId);
    expect(parent.traceContext.traceId, startsWith('trace-'));
    expect(parent.traceContext.spanId, startsWith('span-'));
    expect(child.traceContext.spanId, startsWith('span-'));
    expect(parent.traceContext.parentSpanId, isNull);
    expect(child.traceContext.parentSpanId, parent.traceContext.spanId);
    expect(child.traceContext.spanId, isNot(parent.traceContext.spanId));
  });

  test('metadata failures do not break successful dispatches', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(loggingProvider.notifier)
        .dispatch(const ThrowMetadataEvent());

    expect(
      container.read(loggingProvider),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 20),
    );
  });

  test('metadata failures do not mask original event handler errors', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(logger)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(loggingProvider.notifier)
          .dispatch(const ThrowEventAndMetadataEvent()),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'handler failed',
        ),
      ),
    );

    final failed = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventFailed,
    );
    expect(failed.eventName, 'ThrowEventAndMetadataEvent');
    expect(
      failed.error,
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'handler failed',
      ),
    );
    expect(failed.stackTrace, isNotNull);
    expect(failed.metadata, containsPair('controllerScope', 'sample-logging'));
    expect(failed.metadata, isNot(contains('kind')));
  });

  test('logger failures do not break application flow', () async {
    final container = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(ThrowingEventLogger())],
    );
    addTearDown(container.dispose);

    await container
        .read(loggingProvider.notifier)
        .dispatch(const IncrementEvent());

    expect(
      container.read(loggingProvider),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 1),
    );
  });

  test('hasChanged does not invoke AsyncData payload equality', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(logger)],
    );
    addTearDown(container.dispose);

    await container
        .read(explodingEqualityProvider.notifier)
        .dispatch(const ExplodingEqualityEvent());

    final completed = logger.records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted,
    );
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
    expect(
      () => record.stateMetadata['state'] = 'changed',
      throwsUnsupportedError,
    );
  });

  test(
    'TraceContext.run exposes current context only inside the async zone',
    () async {
      final context = TraceContext.root(startedAt: DateTime.utc(2026, 6));

      expect(TraceContext.current, isNull);
      await TraceContext.run(context, () async {
        await Future<void>.delayed(Duration.zero);
        expect(TraceContext.current, same(context));
      });
      expect(TraceContext.current, isNull);
    },
  );

  test(
    'EventDispatchContext.run exposes current context inside the async zone',
    () async {
      final traceContext = TraceContext.root(startedAt: DateTime.utc(2026, 6));
      final dispatchContext = EventDispatchContext(
        traceContext: traceContext,
        controllerName: 'LoggingController',
        eventName: 'IncrementEvent',
        startedAt: traceContext.startedAt,
      );

      expect(EventDispatchContext.current, isNull);
      await EventDispatchContext.run(dispatchContext, () async {
        await Future<void>.delayed(Duration.zero);
        expect(TraceContext.current, same(traceContext));
        expect(EventDispatchContext.current, same(dispatchContext));
      });
      expect(EventDispatchContext.current, isNull);
    },
  );

  test('EventDispatchContext snapshots metadata maps', () {
    final metadata = <String, Object?>{'kind': 'original'};
    final traceContext = TraceContext.root(startedAt: DateTime.utc(2026, 6));
    final dispatchContext = EventDispatchContext(
      traceContext: traceContext,
      controllerName: 'LoggingController',
      eventName: 'IncrementEvent',
      startedAt: traceContext.startedAt,
      metadata: metadata,
    );

    metadata['kind'] = 'mutated';

    expect(dispatchContext.metadata, containsPair('kind', 'original'));
    expect(
      () => dispatchContext.metadata['kind'] = 'changed',
      throwsUnsupportedError,
    );
  });
}
