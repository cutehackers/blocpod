# blocpod_arch_logger

Bridge adapter between `blocpod_arch` event records and `blocpod_logger` sinks.

This package owns:

- `BlocpodEventLogFormatter`
- `EventLogRecordFormatter`
- `PrettyEventLogRecordFormatter`
- `eventLogPhaseLabel`
- `BlocpodEventLogger`

`blocpod_arch_logger` is the only package in this workspace that should depend on both `blocpod_arch` and `blocpod_logger`.

## Usage

Install the bridge by overriding `eventLoggerProvider` at the application boundary:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

ProviderScope(
  overrides: [
    eventLoggerProvider.overrideWithValue(
      BlocpodEventLogger(DebugPrintLogSink()),
    ),
  ],
  child: const Placeholder(),
);
```

`BlocpodEventLogger` converts `EventLogRecord` values into `BlocpodLogEntry`
values and isolates sink failures from application flow. The formatter includes
the observer phase, trace/span ids, event name, transition index, state kinds,
optional sanitized state labels/metadata, duration, errors, and stack traces.

## Formatter Styles

The default `EventLogRecordFormatter` is compact and structured. It is best for log sinks that index metadata:

```dart
eventLoggerProvider.overrideWithValue(
  BlocpodEventLogger(DebugPrintLogSink()),
);
```

Compact output uses log-friendly phase labels such as `event.started`, `state.transition`, and `event.completed`.
Use `eventLogPhaseLabel` when custom formatters need the same phase labels.

For local debugging, use `PrettyEventLogRecordFormatter`:

```dart
eventLoggerProvider.overrideWithValue(
  BlocpodEventLogger(
    DebugPrintLogSink(),
    formatter: const PrettyEventLogRecordFormatter(),
  ),
);
```

Blocpod does not emit a separate BLoC-style `onChange` phase. `transition` is the canonical event-attributed state-assignment record. Pretty output renders the same transition record in a human-readable form instead of duplicating the core record stream.
Pretty messages show metadata key summaries only; metadata values remain in `BlocpodLogEntry.metadata` for sink-level redaction and indexing.
