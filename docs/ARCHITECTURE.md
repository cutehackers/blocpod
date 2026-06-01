# Blocpod Architecture

Blocpod keeps Riverpod as the provider runtime while standardizing BLoC-like event dispatch, state transition logging, and clean architecture primitives in workspace packages.

## Core Architecture Source Contract

Blocpod's architecture source contract lives in the workspace packages:

1. `packages/arch/lib/src/result.dart`
2. `packages/arch/lib/src/use_case.dart`
3. `packages/arch/lib/src/event_controller.dart`
4. `packages/arch/lib/src/trace_context.dart`
5. `packages/arch/lib/src/event_log_record.dart`
6. `packages/arch/lib/src/event_logger.dart`
7. `packages/logger/lib/src/`
8. `packages/arch_logger/lib/src/`

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
