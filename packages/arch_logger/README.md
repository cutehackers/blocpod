# blocpod_arch_logger

Bridge adapter between `blocpod_arch` event records and `blocpod_logger` sinks.

This package owns:

- `BlocpodEventLogFormatter`
- `EventLogRecordFormatter`
- `PrettyEventLogRecordFormatter`
- `eventLogPhaseLabel`
- `BlocpodEventLogger`

`blocpod_arch_logger` is the only package in this workspace that should depend
on both `blocpod_arch` and `blocpod_logger`.

## Usage

Install the bridge by overriding `eventLoggerProvider` at the application
boundary:

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
the observer phase, dedicated sequence/trace fields, event name, transition
index, state kinds, optional state labels, nested `eventMetadata` /
`stateMetadata`, duration, errors, and stack traces.

`EventLogRecord.metadata` does not flatten into top-level logger fields anymore.
Use the dedicated `BlocpodLogEntry.sequence`, `traceId`, `spanId`, and
`parentSpanId` fields, and read remaining payload from `attributes`.

## Formatter styles

The default `EventLogRecordFormatter` is compact and structured. It is best for
log sinks that index metadata:

```dart
eventLoggerProvider.overrideWithValue(
  BlocpodEventLogger(DebugPrintLogSink()),
);
```

Compact output uses log-friendly phase labels such as `state.established`,
`event.started`, `state.transition`, and `event.completed`. Use
`eventLogPhaseLabel` when custom formatters need the same phase labels.

For local debugging, pair `PrettyEventLogRecordFormatter` with
`PrettyLogEncoder`:

```dart
eventLoggerProvider.overrideWithValue(
  BlocpodEventLogger(
    DebugPrintLogSink(
      encoder: const PrettyLogEncoder(
        detail: PrettyLogDetail.verbose,
      ),
    ),
    formatter: const PrettyEventLogRecordFormatter(),
  ),
);
```

Build/dispatch records follow `controllerCreated → initialStateEstablished →
eventStarted → transition* → eventCompleted | eventFailed`.
`state.established` is emitted once for the first terminal, non-loading build
state; canceled builds and intermediate retry loading states are ignored. It has
no event or previous state; its sanitized state summaries come from `stateLabel`
and `stateMetadata`, with the final state supplied as both `previous` and
`next`. A synchronous or asynchronous terminal error carries its `error` and
`stackTrace`.
`controllerDisposed` records the first Riverpod ref disposal signal registered
by the controller. Provider invalidation may emit it before a rebuild on the
same notifier, so it is not proof that the notifier instance was destroyed.

Blocpod does not emit a separate BLoC-style `onChange` phase. `transition` is
the canonical event-attributed state-assignment record, so direct assignments
outside `dispatch` remain intentionally unobserved. Pretty output renders the
same transition record in a human-readable form instead of duplicating the core
record stream.

Example pretty entry:

```text
12:00:00.000Z INFO  ✅ CounterController · IncrementEvent completed data(count:0) → data(count:1) in 12ms
  sequence=42 trace=trace-1/span-2 parent=span-1
  attributes={phase: event.completed, controllerName: CounterController, eventName: IncrementEvent, durationMicros: 12000, previousStateKind: data, nextStateKind: data, eventMetadata: {feature: counter}, stateMetadata: {changedBy: 1}}
```

Migration details:

- `recordSequence` now maps to `BlocpodLogEntry.sequence`.
- Trace IDs no longer travel inside metadata; they map to dedicated trace
  fields.
- Event payload lives under `attributes['eventMetadata']`.
- State payload lives under `attributes['stateMetadata']`.
- Sensitive-data policy belongs to the application or sink adapter that
  forwards logs beyond Blocpod.
