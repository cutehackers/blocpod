# Blocpod Conventions

## Imports

Applications should import Blocpod architecture primitives through the public barrel:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
```

Avoid importing private `src/` files from other packages.

## Controllers

- Controllers expose `dispatch` as their public action API.
- Event-specific handlers remain private implementation details.
- Keep domain use cases independent from logging adapters.

## Dependency Direction

- `blocpod_arch` must not depend on `blocpod_logger`.
- `blocpod_logger` must not depend on `blocpod_arch`.
- `blocpod_arch_logger` is the only bridge package that depends on both.

## Logging

- Core event logging flows through `EventControllerNotifier.dispatch`.
- `blocpod_arch` emits `EventLogRecord` values through `eventLoggerProvider`.
- Controller build/dispatch logs follow `controllerCreated → initialStateEstablished → eventStarted → transition* → eventCompleted | eventFailed`.
- `initialStateEstablished` is emitted once for the first terminal, non-loading build state. Canceled builds and intermediate retry loading states are ignored. It has no event or previous state; it uses existing `stateLabel` and `stateMetadata` hooks, passing the final state as both `previous` and `next`. A synchronous or asynchronous terminal error includes `error` and `stackTrace`.
- `controllerDisposed` records the first Riverpod ref disposal signal registered by the controller. Provider invalidation may emit it before a rebuild on the same notifier; it is not a final notifier-destruction signal.
- Compact formatters render the phase as `state.established`.
- Direct `state = ...` assignments outside `dispatch` remain intentionally unobserved.
- The default logger is `NoopEventLogger`.
- Applications install concrete logging through provider overrides, such as `BlocpodEventLogger(DebugPrintLogSink())`.
- Keep verbose or diagnostic metadata sanitized.
- Use `stateLabel` and `stateMetadata` only for payload-free state summaries.
- Do not log secrets, tokens, credentials, passwords, or full raw payloads that may contain private data.
