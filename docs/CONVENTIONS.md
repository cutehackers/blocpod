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
- Controller logs include lifecycle, event start, per-`state = ...` transition, event completion, and event failure phases.
- The default logger is `NoopEventLogger`.
- Applications install concrete logging through provider overrides, such as `BlocpodEventLogger(DebugPrintLogSink())`.
- Keep verbose or diagnostic metadata sanitized.
- Use `stateLabel` and `stateMetadata` only for payload-free state summaries.
- Do not log secrets, tokens, credentials, passwords, or full raw payloads that may contain private data.
