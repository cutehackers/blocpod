# blocpod_arch

Core Riverpod event architecture package for Blocpod.

This package owns:

- `Result<T>`, `Ok<T>`, and `Error<T>`
- `UseCase<Output, Params>` and `NoParams`
- `EventController<E>` and `EventControllerNotifier<S, E>`
- `RefEventDispatcherX` and `WidgetRefEventDispatcherX`
- `TraceContext`
- `EventLogRecord`, `EventLogPhase`, and `AsyncValueKind`
- `EventLogger`, `NoopEventLogger`, and `eventLoggerProvider`

`blocpod_arch` depends on Flutter and `flutter_riverpod`. It must not depend on `blocpod_logger` or any concrete logging sink.

## Usage

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class CounterEvent {
  const CounterEvent();
}

final class IncrementCounterEvent extends CounterEvent {
  const IncrementCounterEvent();
}

final counterProvider = AsyncNotifierProvider<CounterController, int>(
  CounterController.new,
);

final class CounterController extends EventControllerNotifier<int, CounterEvent> {
  @override
  Future<int> build() async => 0;

  @override
  Future<void> onEvent(CounterEvent event) async {
    switch (event) {
      case IncrementCounterEvent():
        final current = state.value ?? 0;
        state = AsyncData(current + 1);
    }
  }

  @override
  String? stateLabel(AsyncValue<int> state) {
    return switch (state) {
      AsyncData<int>() => 'ready',
      AsyncLoading<int>() => 'loading',
      AsyncError<int>() => 'error',
    };
  }
}
```

Widgets and providers dispatch events through the public boundary:

```dart
await ref.dispatch(counterProvider, const IncrementCounterEvent());
```

`EventControllerNotifier` build/dispatch records follow
`controllerCreated → initialStateEstablished → eventStarted → transition* → eventCompleted | eventFailed`.

`initialStateEstablished` is emitted once for the first terminal, non-loading
`build()` state. Canceled builds and intermediate retry loading states are ignored.
It has no event or previous state and invokes the existing
`stateLabel` and `stateMetadata` hooks; for initialization, the final state is passed
as both `previous` and `next` to `stateMetadata`. A synchronous or asynchronous
terminal `AsyncError` carries its `error` and `stackTrace`. `controllerDisposed`
records the first Riverpod ref disposal signal registered by the controller.
Provider invalidation may emit it before a rebuild on the same notifier, so it does
not prove notifier destruction. During dispatch, one `transition` is recorded for each
`state = ...` assignment. Direct assignments outside `dispatch` remain intentionally
unobserved. State logging is payload-free by default; use `stateLabel` and
`stateMetadata` only for sanitized summaries.

## Observation semantics

Each notifier owns its active dispatch contexts by identity. A context can
attribute state only while its handler is active and only to the notifier that
created it. Cross-controller writes, writes inherited after completion, and
logger-triggered direct writes still update their target state but are not
attributed to the observed event.

Terminal records use an event-local outcome: the state admitted at dispatch
start, replaced by the latest state assignment owned by that event. Concurrent
sibling dispatches cannot overwrite one another's completion record. An awaited
same-controller child contributes its outcome to its still-active parent unless
the parent performs a later write. Dart zones do not reveal whether an in-flight
child `Future` will eventually be awaited, so a child that finishes while its
parent remains active is treated as causal even when its `Future` was not
awaited. A child that finishes after the parent closes is not folded into it.

`startedAt` is the lifecycle occurrence or dispatch-span start. `occurredAt` is
the UTC time when that individual phase occurred, and `recordSequence` is the
strictly increasing occurrence order within the current Dart isolate.
Dispatch `duration` comes from a monotonic `Stopwatch`, not wall-clock
subtraction. Blocpod allocates occurrence data before logger delivery, so queue
delay never changes `occurredAt` or `recordSequence`.

All framework writes, including the logger captured for `controllerDisposed`,
pass through one isolate-wide synchronous FIFO gate. Logger callbacks never
nest: records created by a callback are appended and delivered after it returns.
Each callback runs with both dispatch and trace context masked, so callback
work is not attributed to the observed event and callback-started dispatches
begin root traces. A failing callback is isolated and draining continues.
Delivery remains synchronous; a slow logger delays the emitting state change,
dispatch, build, or disposal operation. Adapters may buffer downstream output,
but Blocpod itself does not schedule microtasks, drop records, or bound the
queue.
