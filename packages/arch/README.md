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

During dispatch, `EventControllerNotifier` records `eventStarted`, one `transition`
for each `state = ...` assignment, and `eventCompleted` or `eventFailed`. It also
records controller create/dispose lifecycle events. State logging is payload-free by
default; use `stateLabel` and `stateMetadata` only for sanitized summaries.
