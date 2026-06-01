# Blocpod Riverpod Event Architecture Design

## Goal

Create a reusable Dart/Flutter package family named **Blocpod** that extracts Pit Wall's Riverpod event-controller pattern
into a small, composable architecture library.

Blocpod should provide a BLoC-like developer experience on top of Riverpod:

- UI dispatches typed events.
- Controllers handle events through one dispatch boundary.
- State transitions are observable.
- Use cases and repositories keep clean architecture boundaries.
- Logging and traceability are available without forcing a specific logger package on the core architecture.

## Product Positioning

Blocpod is not a replacement for Riverpod. It is a thin event architecture layer for teams that want BLoC-style event
traceability while keeping Riverpod's provider model, `AsyncNotifier`, dependency injection, and testing ergonomics.

The name intentionally signals "BLoC-like Riverpod" rather than a full BLoC clone.

## Package Layout

Use three packages under `packages/`:

```text
packages/
  arch/
    pubspec.yaml        # package name: blocpod_arch
    lib/

  logger/
    pubspec.yaml        # package name: blocpod_logger
    lib/

  arch_logger/
    pubspec.yaml        # package name: blocpod_arch_logger
    lib/
```

The folder names stay short for local workspace ergonomics. The published package names carry the `blocpod_` prefix.

## Package Responsibilities

### `blocpod_arch`

`blocpod_arch` is the core architecture package. It owns the stable event-controller and clean-architecture primitives.

Public API:

- `EventController<E>`
- `EventControllerNotifier<S, E>`
- `RefEventDispatcherX`
- `WidgetRefEventDispatcherX`
- `Result<T>`, `Ok<T>`, `Error<T>`
- `UseCase<Output, Params>`
- `NoParams`
- `TraceContext`
- `EventLogRecord`
- `EventLogger`
- `NoopEventLogger`
- `eventLoggerProvider`

Responsibilities:

- Provide the dispatch lifecycle.
- Capture before/after `AsyncValue<S>` transitions.
- Generate or propagate trace context for every dispatch.
- Expose logger interfaces and log-record value types.
- Default to no-op logging.
- Avoid any dependency on concrete logger libraries.

Dependencies:

- `flutter`
- `flutter_riverpod`

No dependency on `blocpod_logger`, `logger`, Sentry, OpenTelemetry, Crashlytics, or any other output sink.

### `blocpod_logger`

`blocpod_logger` is the generic logging package for Blocpod adapters and applications.

Public API:

- `BlocpodLogSink`
- `BlocpodLogLevel`
- `BlocpodLogEntry`
- `DebugPrintLogSink`
- optional formatting helpers for local development output

Responsibilities:

- Define a small logging sink abstraction.
- Provide development-friendly console/debug output.
- Keep output concerns separate from event architecture.
- Avoid importing Riverpod architecture primitives.

Dependencies:

- `flutter` only if `DebugPrintLogSink` uses Flutter's `debugPrint`.
- No dependency on `blocpod_arch`.

### `blocpod_arch_logger`

`blocpod_arch_logger` is the bridge package. It connects `blocpod_arch` event records to `blocpod_logger` sinks.

Public API:

- `BlocpodEventLogger`
- `EventLogRecordFormatter`
- convenience provider overrides for common local-development wiring

Responsibilities:

- Implement `EventLogger` from `blocpod_arch`.
- Convert `EventLogRecord` into `BlocpodLogEntry`.
- Preserve the trace id, event name, controller name, duration, state transition, and error metadata.
- Keep app setup simple without coupling `blocpod_arch` to a concrete logger dependency.

Dependencies:

- `blocpod_arch`
- `blocpod_logger`

## Architecture Contract

### Event Dispatch Boundary

Every user or system action enters the architecture through `dispatch`.

```dart
abstract class EventController<E> {
  Future<void> dispatch(E event);
}

abstract class EventControllerNotifier<S, E> extends AsyncNotifier<S> implements EventController<E> {
  @override
  Future<void> dispatch(E event) async {
    // Captures trace context, before state, duration, after state, and errors.
  }

  @protected
  Future<void> onEvent(E event);
}
```

Controllers expose only `dispatch` as their public action API. Event-specific handlers stay private inside the controller.
Widgets dispatch events through `ref.dispatch(provider, event)`.

### Trace Context

`TraceContext` is the minimal correlation object for event-level observability.

Fields:

- `traceId`
- `spanId`
- `parentSpanId`
- `startedAt`

Rules:

- A root `TraceContext` is created when dispatch starts and no current trace exists.
- Nested dispatches reuse the current trace id and create child spans.
- Application code should not pass `traceId` through use case parameters.
- Trace context is an observability concern, not a domain model.

### Event Log Record

`EventLogRecord` is the core structured event emitted by `blocpod_arch`.

Fields:

- `traceContext`
- `controllerName`
- `eventName`
- `startedAt`
- `duration`
- `beforeStateKind`
- `afterStateKind`
- `hasChanged`
- `error`
- `stackTrace`
- `metadata`

State values should not be dumped by default. The default record stores state kind and transition shape, not full object
payloads. Features may add sanitized metadata when useful.

### Logger Contract

`EventLogger` receives `EventLogRecord` values.

```dart
abstract interface class EventLogger {
  void log(EventLogRecord record);
}
```

The default provider returns `NoopEventLogger`, so Blocpod can be installed without any logger adapter.

Applications opt in through provider overrides:

```dart
ProviderScope(
  overrides: [
    eventLoggerProvider.overrideWithValue(
      BlocpodEventLogger(DebugPrintLogSink()),
    ),
  ],
  child: const App(),
);
```

## Dependency Direction

Dependency flow must remain one-way:

```text
blocpod_arch_logger
  depends on blocpod_arch
  depends on blocpod_logger

blocpod_arch
  depends on flutter_riverpod

blocpod_logger
  depends on no Blocpod architecture package
```

Forbidden dependencies:

- `blocpod_arch` must not import `blocpod_logger`.
- `blocpod_logger` must not import `blocpod_arch`.
- Domain use cases must not depend on logger adapters.
- Feature state must not contain trace context.

## Data Flow

```text
Widget
  ref.dispatch(provider, Event)
    ↓
EventControllerNotifier.dispatch()
  creates or enters TraceContext
  captures before AsyncValue
  records start time
    ↓
onEvent(event)
  routes to private handler
    ↓
UseCase
  returns Result<T>
    ↓
Repository / DataSource
  maps external failures to Result.error
    ↓
Controller updates AsyncValue<State>
    ↓
EventControllerNotifier.dispatch()
  captures after AsyncValue
  emits EventLogRecord through EventLogger
```

## Error Handling

Expected domain and data failures continue to use `Result<T>`.

Controller rules:

- Convert `Result.ok` into `AsyncData`.
- Convert screen-level unrecoverable failures into `AsyncError`.
- Keep recoverable, user-facing issues inside state fields.
- Let `dispatch` log thrown errors with the original stack trace.

Logger rules:

- Logging failures must not break application flow.
- `EventLogger` implementations should catch and isolate sink errors.
- Records must not include secrets, credentials, tokens, or full raw payloads.

## Testing Strategy

### `blocpod_arch`

Required tests:

- `Result<T>` exposes typed success and error branches.
- `UseCase` supports `NoParams`.
- `dispatch` routes events to `onEvent`.
- `dispatch` logs before/after state.
- `dispatch` logs thrown errors and preserves stack traces.
- Nested dispatches keep one trace id and create child spans.
- `ref.dispatch` supports regular, `autoDispose`, `family`, and `autoDispose.family` providers.
- Default logger is no-op.

### `blocpod_logger`

Required tests:

- `BlocpodLogEntry` preserves level, message, timestamp, metadata, error, and stack trace.
- `DebugPrintLogSink` formats useful local-development output.
- Formatting does not print sensitive metadata by default.

### `blocpod_arch_logger`

Required tests:

- `BlocpodEventLogger` maps `EventLogRecord` into `BlocpodLogEntry`.
- trace id, event name, controller name, duration, and state transition are preserved.
- error records map to error-level log entries.

### Pit Wall Integration

Required tests after migration:

- Existing dashboard controller behavior still passes.
- Pit Wall imports `blocpod_arch` instead of local `lib/src/core/arch` primitives.
- Optional logger override can be installed without changing controller code.

## Migration Plan For Pit Wall

1. Create the package workspace under `packages/`.
2. Move current architecture primitives into `blocpod_arch`.
3. Add logger primitives to `blocpod_logger`.
4. Add bridge adapter to `blocpod_arch_logger`.
5. Update Pit Wall `pubspec.yaml` to depend on `blocpod_arch` by local path.
6. Replace imports from `package:pit_wall/src/core/arch/...` with `package:blocpod_arch/blocpod_arch.dart`.
7. Remove duplicated local core architecture files only after all app and package tests pass.
8. Update `docs/ARCHITECTURE.md` and `docs/ARCHITECTURE-ko.md` so `Core Architecture Source Contract` points to Blocpod packages.
9. Keep `docs/CONVENTIONS.md` focused on mechanical coding rules and adapter dependency rules.

## Milestones

### Milestone 1: Extract Core

Deliver `blocpod_arch` with current Pit Wall architecture primitives and no-op event logging.

Success criteria:

- Package tests pass.
- Pit Wall can depend on the package by local path.
- Existing controller tests pass without behavior changes.

### Milestone 2: Add Structured Event Logging

Add `TraceContext`, `EventLogRecord`, `EventLogger`, and default no-op provider.

Success criteria:

- Every dispatch can produce a structured event record.
- Logging can be disabled by default.
- Tests prove before/after/error logging.

### Milestone 3: Add Logger Packages

Deliver `blocpod_logger` and `blocpod_arch_logger`.

Success criteria:

- App code can install a debug logger with a provider override.
- `blocpod_arch` has no dependency on `blocpod_logger`.
- Adapter tests prove record-to-log mapping.

### Milestone 4: Update Pit Wall Documentation

Update architecture docs to describe Blocpod as the source contract.

Success criteria:

- English and Korean architecture docs stay aligned.
- Conventions document explains adapter dependency direction.
- No generated-controller guidance conflicts with `EventControllerNotifier`.

## Non-Goals

- Reimplementing the BLoC package.
- Adding event handler registration APIs.
- Adding generated controller classes.
- Adding OpenTelemetry, Sentry, Crashlytics, or external logger adapters in the first implementation.
- Passing trace ids through domain params.
- Logging full state payloads by default.
- Replacing Riverpod's provider model.

## Design Decisions

- Blocpod uses package names with the `blocpod_` prefix and local folder names without the prefix.
- `blocpod_arch` owns architecture contracts, not output formatting.
- `blocpod_logger` owns log sinks, not Riverpod event semantics.
- `blocpod_arch_logger` is the only package that knows both sides.
- Optional logger support is modeled through sibling packages and provider overrides, not optional imports.
- The default runtime behavior is no-op logging.

## Review Checklist

- The design keeps architecture and logging output decoupled.
- The package dependency graph has no cycles.
- The event-controller API remains simple for feature authors.
- Traceability does not leak into domain models.
- The plan can be implemented incrementally without changing Pit Wall behavior first.
