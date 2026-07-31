# Blocpod Architecture

Blocpod keeps Riverpod as the provider runtime while standardizing BLoC-like event dispatch, state transition logging, and clean architecture primitives in workspace packages.

## Core Architecture Source Contract

Blocpod's architecture source contract lives in the workspace packages:

1. `packages/arch/lib/src/result.dart`
2. `packages/arch/lib/src/use_case.dart`
3. `packages/arch/lib/src/event_controller.dart`
4. `packages/arch/lib/src/event_dispatch_context.dart`
5. `packages/arch/lib/src/trace_context.dart`
6. `packages/arch/lib/src/observation_runtime.dart`
7. `packages/arch/lib/src/event_log_record.dart`
8. `packages/arch/lib/src/event_logger.dart`
9. `packages/logger/lib/src/`
10. `packages/arch_logger/lib/src/`

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

The observer stream follows the BLoCObserver model while staying Riverpod-native. Build/dispatch records follow `controllerCreated → initialStateEstablished → eventStarted → transition* → eventCompleted | eventFailed`:

- `controllerCreated` is emitted before the first build.
- `initialStateEstablished` is emitted once for the first terminal, non-loading `build()` state. Canceled builds and intermediate retry loading states are ignored. It has no event or previous state, invokes the existing sanitized `stateLabel` and `stateMetadata` hooks with the final state as both `previous` and `next`, and carries `error` and `stackTrace` for synchronous or asynchronous terminal errors.
- `eventStarted` is emitted when `dispatch` enters an event handler.
- `transition` is emitted after each successful `state = ...` assignment while an event dispatch context is active. Setter calls that throw are not recorded as owned transitions or outcomes, even if Riverpod mutated internal state before throwing. Synchronous logger callbacks therefore observe the committed next state for every emitted transition. This is Blocpod's canonical state-assignment observation: it carries the event name, trace/span ids, previous/next `AsyncValue` kinds, optional sanitized state labels/metadata, and `hasChanged` information.
- `eventCompleted` or `eventFailed` is emitted when the handler exits.
- `controllerDisposed` records the first Riverpod ref disposal signal registered by the controller. Provider invalidation may emit it before a rebuild on the same notifier, so it is not a final notifier-destruction signal.

Blocpod intentionally does not emit a separate BLoC-style `onChange` phase. BLoC's `onChange` observes `BlocBase.emit` with only current and next state, while Blocpod's `transition` observes Riverpod `AsyncValue` state assignments inside dispatch and keeps the event attribution. Direct non-dispatch assignments remain intentionally unobserved. Human-readable formatters may render a transition in a BLoC-observer-like style, but the core record stream stays single-source and avoids duplicate state-change records.

The internal `EventDispatchContext` is stored in the async zone during dispatch
and carries notifier ownership by identity, active lifetime, parent context,
trace/span ids, event name, sanitized event metadata, start time, and transition
index. It attributes a state assignment only while active and only to its owning
notifier. Cross-controller writes and work inherited after context closure may
still change state, but they are not recorded as transitions of the observed
event. Nested dispatches create child spans inside the same trace. Concurrent
dispatches keep attribution through their async zone.

Each active dispatch also owns an event-local observation ledger. Its terminal
state is the state at admission or the latest state write owned by that event,
not a completion-time read of shared controller state. Concurrent siblings
therefore retain independent outcomes. An awaited same-controller child folds
its outcome into a still-active parent, subject to later parent writes. Dart
zones cannot reveal whether an in-flight child `Future` will later be awaited,
so a child that settles while its parent is active is treated as causal even if
that `Future` was not awaited. A child settling after parent closure is not
folded.

The internal observation runtime has isolate lifetime and owns both occurrence
sequencing and logger delivery. `startedAt` identifies the lifecycle occurrence
or dispatch span start; `occurredAt` captures each phase occurrence in UTC; and
`recordSequence` is a strictly increasing, isolate-local occurrence order.
Dispatch duration uses monotonic `Stopwatch.elapsed`. Occurrence fields are
allocated before delivery, so logger latency cannot change timestamps or
sequence.

Every framework logger write, including the logger captured for
`controllerDisposed`, enters one synchronous isolate-wide FIFO queue together
with its immutable `EventLogRecord` and target `EventLogger`. The first emitter
drains immediately. If a callback synchronously creates another record, that
record is appended and delivered only after the current callback returns, so
callback depth never exceeds one and delivery follows `recordSequence`.
Callbacks run with both event-dispatch and trace zone markers explicitly
masked; logger-started state work is independent and logger-started dispatches
begin root traces. Each logger failure is caught independently and draining
continues without changing state, dispatch results, original handler errors,
provider lifecycle, or disposal.

This boundary is intentionally synchronous: a slow logger delays the emitter.
Blocpod does not add microtasks, a bounded queue, a drop policy, or durable
delivery. Asynchronous buffering, when needed, belongs in the adapter.

State logging is payload-free by default. Records include state kinds such as `loading`, `data`, or `error`; controllers may opt in to sanitized `stateLabel` and `stateMetadata` summaries. Controllers must not log raw state payloads, secrets, tokens, credentials, or passwords.
