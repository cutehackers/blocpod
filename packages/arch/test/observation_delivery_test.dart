import 'dart:async';

import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch/src/event_dispatch_context.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class OuterEvent {
  const OuterEvent();
}

final class IncrementOuterEvent extends OuterEvent {
  const IncrementOuterEvent();
}

sealed class InnerEvent {
  const InnerEvent();
}

final class IncrementInnerEvent extends InnerEvent {
  const IncrementInnerEvent();
}

final outerProvider = AsyncNotifierProvider<OuterController, int>(OuterController.new);

final innerProvider = AsyncNotifierProvider<InnerController, int>(InnerController.new);

final hookReentrantProvider = AsyncNotifierProvider.family<HookReentrantController, int, void Function()>(
  HookReentrantController.new,
);

final class OuterController extends EventControllerNotifier<int, OuterEvent> {
  @override
  Future<int> build() async => 0;

  @override
  Future<void> onEvent(OuterEvent event) async {
    switch (event) {
      case IncrementOuterEvent():
        state = AsyncData((state.value ?? 0) + 1);
    }
  }

  void setDirectly(int value) {
    state = AsyncData(value);
  }

  @override
  String? stateLabel(AsyncValue<int> state) {
    return switch (state) {
      AsyncData<int>(:final value) => 'value:$value',
      AsyncLoading<int>() => 'loading',
      AsyncError<int>() => 'error',
    };
  }
}

final class InnerController extends EventControllerNotifier<int, InnerEvent> {
  @override
  Future<int> build() async => 0;

  @override
  Future<void> onEvent(InnerEvent event) async {
    switch (event) {
      case IncrementInnerEvent():
        state = AsyncData((state.value ?? 0) + 1);
    }
  }

  @override
  String? stateLabel(AsyncValue<int> state) {
    return switch (state) {
      AsyncData<int>(:final value) => 'value:$value',
      AsyncLoading<int>() => 'loading',
      AsyncError<int>() => 'error',
    };
  }
}

final class HookReentrantController extends EventControllerNotifier<int, OuterEvent> {
  HookReentrantController(this.onNextStateLabel);

  final void Function() onNextStateLabel;
  bool _didReenter = false;

  @override
  Future<int> build() async => 0;

  @override
  Future<void> onEvent(OuterEvent event) async {
    switch (event) {
      case IncrementOuterEvent():
        state = AsyncData((state.value ?? 0) + 1);
    }
  }

  @override
  String? stateLabel(AsyncValue<int> state) {
    if (!_didReenter) {
      if (state case AsyncData<int>(value: 1)) {
        _didReenter = true;
        onNextStateLabel();
      }
    }
    return switch (state) {
      AsyncData<int>(:final value) => 'value:$value',
      AsyncLoading<int>() => 'loading',
      AsyncError<int>() => 'error',
    };
  }
}

final class CallbackLogger implements EventLogger {
  CallbackLogger(this.callback);

  final void Function(EventLogRecord record) callback;

  @override
  void log(EventLogRecord record) {
    callback(record);
  }
}

void main() {
  test('reentrant records use one isolate-wide non-reentrant FIFO gate', () {
    late ProviderContainer innerContainer;
    var callbackDepth = 0;
    var maxCallbackDepth = 0;
    var createdInner = false;
    final delivered = <({String loggerIdentity, EventLogRecord record})>[];

    void recordDelivery(String loggerIdentity, EventLogRecord record) {
      callbackDepth += 1;
      maxCallbackDepth = callbackDepth > maxCallbackDepth ? callbackDepth : maxCallbackDepth;
      try {
        delivered.add((loggerIdentity: loggerIdentity, record: record));
        if (!createdInner && loggerIdentity == 'outer' && record.phase == EventLogPhase.controllerCreated) {
          createdInner = true;
          innerContainer.read(innerProvider.notifier);
        }
      } finally {
        callbackDepth -= 1;
      }
    }

    innerContainer = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(CallbackLogger((record) => recordDelivery('inner', record)))],
    );
    final outerContainer = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(CallbackLogger((record) => recordDelivery('outer', record)))],
    );
    addTearDown(innerContainer.dispose);
    addTearDown(outerContainer.dispose);

    outerContainer.read(outerProvider.notifier);

    expect(maxCallbackDepth, 1);
    expect(delivered.take(2).map((entry) => entry.loggerIdentity), <String>['outer', 'inner']);
    expect(delivered.take(2).map((entry) => entry.record.phase), <EventLogPhase>[
      EventLogPhase.controllerCreated,
      EventLogPhase.controllerCreated,
    ]);
    final sequences = delivered.take(2).map((entry) => entry.record.recordSequence!).toList();
    expect(sequences, orderedEquals(<int>[sequences.first, sequences.first + 1]));
  });

  test('hook reentry delivers the reserved outer transition before later records', () async {
    late ProviderContainer innerContainer;
    var hookRan = false;
    final delivered = <({String loggerIdentity, EventLogRecord record})>[];
    final innerLogger = CallbackLogger((record) => delivered.add((loggerIdentity: 'inner', record: record)));
    final outerLogger = CallbackLogger((record) => delivered.add((loggerIdentity: 'outer', record: record)));
    innerContainer = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(innerLogger)]);
    final outerContainer = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(outerLogger)]);
    addTearDown(innerContainer.dispose);
    addTearDown(outerContainer.dispose);
    void reenterFromStateLabel() {
      hookRan = true;
      innerContainer.read(innerProvider.notifier);
    }

    final provider = hookReentrantProvider(reenterFromStateLabel);
    final controller = outerContainer.read(provider.notifier);
    await outerContainer.read(provider.future);
    delivered.clear();

    await controller.dispatch(const IncrementOuterEvent());

    expect(hookRan, isTrue);
    final outerTransitionIndex = delivered.indexWhere(
      (entry) => entry.loggerIdentity == 'outer' && entry.record.phase == EventLogPhase.transition,
    );
    final innerCreationIndex = delivered.indexWhere(
      (entry) => entry.loggerIdentity == 'inner' && entry.record.phase == EventLogPhase.controllerCreated,
    );
    expect(outerTransitionIndex, isNonNegative);
    expect(innerCreationIndex, isNonNegative);
    expect(outerTransitionIndex, lessThan(innerCreationIndex));

    final outerTransition = delivered[outerTransitionIndex].record;
    final innerCreation = delivered[innerCreationIndex].record;
    expect(outerTransition.transitionIndex, 1);
    expect(innerCreation.recordSequence, outerTransition.recordSequence! + 1);
    final sequences = delivered.map((entry) => entry.record.recordSequence!).toList();
    expect(sequences, orderedEquals(sequences.toList()..sort()));
  });

  test('failed lazy logger resolution cannot block later framework records', () async {
    late ProviderContainer innerContainer;
    var resolutionAttempts = 0;
    final innerRecords = <EventLogRecord>[];
    innerContainer = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(CallbackLogger(innerRecords.add))],
    );
    final outerContainer = ProviderContainer(
      overrides: [
        eventLoggerProvider.overrideWith((ref) {
          resolutionAttempts += 1;
          innerContainer.read(innerProvider.notifier);
          throw StateError('logger resolution failed');
        }),
      ],
    );
    addTearDown(innerContainer.dispose);
    addTearDown(outerContainer.dispose);

    outerContainer.read(outerProvider.notifier);
    await innerContainer.read(innerProvider.future);
    await innerContainer.read(innerProvider.notifier).dispatch(const IncrementInnerEvent());

    expect(resolutionAttempts, greaterThanOrEqualTo(1));
    expect(
      innerRecords.map((record) => record.phase),
      containsAllInOrder(<EventLogPhase>[
        EventLogPhase.controllerCreated,
        EventLogPhase.initialStateEstablished,
        EventLogPhase.eventStarted,
        EventLogPhase.transition,
        EventLogPhase.eventCompleted,
      ]),
    );
    final sequences = innerRecords.map((record) => record.recordSequence!).toList();
    expect(sequences, orderedEquals(sequences.toList()..sort()));
  });

  test('a callback that enqueues then throws does not strand queued or later records', () async {
    late ProviderContainer innerContainer;
    var firstInvocation = true;
    final callbackOrder = <String>[];
    final delivered = <EventLogRecord>[];
    final logger = CallbackLogger((record) {
      delivered.add(record);
      if (firstInvocation) {
        firstInvocation = false;
        callbackOrder.add('outer entered');
        innerContainer.read(innerProvider.notifier);
        callbackOrder.add('outer enqueued');
        throw StateError('logger failed after enqueue');
      }
      callbackOrder.add('record delivered');
    });
    innerContainer = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    final outerContainer = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(innerContainer.dispose);
    addTearDown(outerContainer.dispose);

    final outer = outerContainer.read(outerProvider.notifier);

    expect(callbackOrder, <String>['outer entered', 'outer enqueued', 'record delivered']);

    await Future.wait(<Future<int>>[
      outerContainer.read(outerProvider.future),
      innerContainer.read(innerProvider.future),
    ]);
    await outer.dispatch(const IncrementOuterEvent());

    expect(
      delivered,
      contains(isA<EventLogRecord>().having((record) => record.phase, 'phase', EventLogPhase.eventCompleted)),
    );
    final sequences = delivered.map((record) => record.recordSequence!).toList();
    expect(sequences, orderedEquals(sequences.toList()..sort()));
  });

  test('logger callbacks run without dispatch or trace context', () async {
    final observed = <({EventLogPhase phase, EventDispatchContext? dispatchContext, TraceContext? traceContext})>[];
    final microtaskContext = Completer<({EventDispatchContext? dispatchContext, TraceContext? traceContext})>();
    final logger = CallbackLogger((record) {
      observed.add((
        phase: record.phase,
        dispatchContext: EventDispatchContext.current,
        traceContext: TraceContext.current,
      ));
      if (record.phase == EventLogPhase.transition && !microtaskContext.isCompleted) {
        scheduleMicrotask(() {
          microtaskContext.complete((
            dispatchContext: EventDispatchContext.current,
            traceContext: TraceContext.current,
          ));
        });
      }
    });
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    final ambientTrace = TraceContext.root(startedAt: DateTime.utc(2026, 7, 31));

    await TraceContext.run(ambientTrace, () async {
      final controller = container.read(outerProvider.notifier);
      await controller.dispatch(const IncrementOuterEvent());
      container.dispose();
      expect(TraceContext.current, same(ambientTrace));
    });
    final inheritedContext = await microtaskContext.future;

    const requiredPhases = <EventLogPhase>{
      EventLogPhase.controllerCreated,
      EventLogPhase.initialStateEstablished,
      EventLogPhase.transition,
      EventLogPhase.eventCompleted,
      EventLogPhase.controllerDisposed,
    };
    expect(observed.map((entry) => entry.phase).toSet(), containsAll(requiredPhases));
    for (final entry in observed.where((entry) => requiredPhases.contains(entry.phase))) {
      expect(entry.dispatchContext, isNull, reason: '${entry.phase} retained dispatch context');
      expect(entry.traceContext, isNull, reason: '${entry.phase} retained trace context');
    }
    expect(inheritedContext.dispatchContext, isNull);
    expect(inheritedContext.traceContext, isNull);
    expect(TraceContext.current, isNull);
  });

  test('dispatch started by a transition logger callback is a root trace', () async {
    late InnerController inner;
    Future<void>? loggerDispatch;
    var startedInner = false;
    final records = <EventLogRecord>[];
    final logger = CallbackLogger((record) {
      records.add(record);
      if (!startedInner && record.phase == EventLogPhase.transition && record.eventName == 'IncrementOuterEvent') {
        startedInner = true;
        loggerDispatch = inner.dispatch(const IncrementInnerEvent());
      }
    });
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    final outer = container.read(outerProvider.notifier);
    inner = container.read(innerProvider.notifier);
    await Future.wait(<Future<int>>[container.read(outerProvider.future), container.read(innerProvider.future)]);

    await outer.dispatch(const IncrementOuterEvent());
    await loggerDispatch;

    final outerCompleted = records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'IncrementOuterEvent',
    );
    final innerCompleted = records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'IncrementInnerEvent',
    );
    final outerTransitions = records.where(
      (record) => record.phase == EventLogPhase.transition && record.eventName == 'IncrementOuterEvent',
    );
    final innerTransition = records.singleWhere(
      (record) => record.phase == EventLogPhase.transition && record.eventName == 'IncrementInnerEvent',
    );
    expect(outerTransitions, hasLength(1));
    expect(innerTransition.traceContext.spanId, innerCompleted.traceContext.spanId);
    expect(innerCompleted.traceContext.parentSpanId, isNull);
    expect(innerCompleted.traceContext.traceId, isNot(outerCompleted.traceContext.traceId));
    expect(innerCompleted.nextStateLabel, 'value:1');
    expect(outerCompleted.nextStateLabel, 'value:1');
  });

  test('direct state mutation by a transition logger is not attributed to the event', () async {
    late OuterController controller;
    var mutated = false;
    final records = <EventLogRecord>[];
    final logger = CallbackLogger((record) {
      records.add(record);
      if (!mutated && record.phase == EventLogPhase.transition && record.eventName == 'IncrementOuterEvent') {
        mutated = true;
        controller.setDirectly(90);
      }
    });
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);
    controller = container.read(outerProvider.notifier);

    await controller.dispatch(const IncrementOuterEvent());

    final transitions = records
        .where((record) => record.phase == EventLogPhase.transition && record.eventName == 'IncrementOuterEvent')
        .toList();
    final completed = records.singleWhere(
      (record) => record.phase == EventLogPhase.eventCompleted && record.eventName == 'IncrementOuterEvent',
    );
    expect(transitions, hasLength(1));
    expect(completed.nextStateLabel, 'value:1');
    expect(container.read(outerProvider), isA<AsyncData<int>>().having((state) => state.value, 'value', 90));
  });
}
