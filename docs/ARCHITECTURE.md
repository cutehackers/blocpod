# Blocpod Architecture

Blocpod keeps Riverpod as the provider runtime while standardizing BLoC-like event dispatch, state transition logging, and clean architecture primitives in workspace packages.

## Core Architecture Source Contract

Blocpod's architecture source contract lives in the workspace packages:

1. `packages/arch/lib/src/result.dart`
2. `packages/arch/lib/src/use_case.dart`
3. `packages/arch/lib/src/event_controller.dart`
4. `packages/arch/lib/src/event_dispatch_context.dart`
5. `packages/arch/lib/src/trace_context.dart`
6. `packages/arch/lib/src/event_log_record.dart`
7. `packages/arch/lib/src/event_logger.dart`
8. `packages/logger/lib/src/`
9. `packages/arch_logger/lib/src/`

Applications import the stable public barrels:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
```

The dependency direction is fixed:

- `blocpod_arch` depends on Flutter and `flutter_riverpod`.
- `blocpod_logger` depends on Flutter for `debugPrint` output.
- `blocpod_arch_logger` depends on `blocpod_arch` and `blocpod_logger`.
- `blocpod_arch` must not import `blocpod_logger`.
- `blocpod_logger` must not import `blocpod_arch`.

Controllers inherit `EventControllerNotifier<State, Event>` and expose only `dispatch` as their public action API. Widgets dispatch events with `ref.dispatch(provider, event)`. Do not create generated `@riverpod` controller classes for this architecture.

## Logging Boundary

`blocpod_arch` emits structured event records through `eventLoggerProvider` and defaults to no-op logging. Applications install concrete output with provider overrides from adapter packages.

The observer stream follows the BLoCObserver model while staying Riverpod-native:

- `controllerCreated` and `controllerDisposed` are emitted from the controller lifecycle.
- `eventStarted` is emitted when `dispatch` enters an event handler.
- `transition` is emitted before each `state = ...` assignment while an event dispatch context is active. This is Blocpod's canonical state-assignment observation: it carries the event name, trace/span ids, previous/next `AsyncValue` kinds, optional sanitized state labels/metadata, and `hasChanged` information.
- `eventCompleted` or `eventFailed` is emitted when the handler exits.

Blocpod intentionally does not emit a separate BLoC-style `onChange` phase. BLoC's `onChange` observes `BlocBase.emit` with only current and next state, while Blocpod's `transition` observes Riverpod `AsyncValue` state assignments inside dispatch and keeps the event attribution. Human-readable formatters may render a transition in a BLoC-observer-like style, but the core record stream stays single-source and avoids duplicate state-change records.

The internal `EventDispatchContext` is stored in the async zone during dispatch and carries the trace/span ids, event name, sanitized event metadata, start time, and transition index. Nested dispatches create child spans inside the same trace. Concurrent dispatches keep attribution through their async zone.

State logging is payload-free by default. Records include state kinds such as `loading`, `data`, or `error`; controllers may opt in to sanitized `stateLabel` and `stateMetadata` summaries. Controllers must not log raw state payloads, secrets, tokens, credentials, or passwords.
