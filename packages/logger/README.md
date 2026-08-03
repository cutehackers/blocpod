# blocpod_logger

Generic structured logging primitives for Blocpod packages.

This package owns:

- `BlocpodLogLevel`
- `BlocpodLogEntry`
- `BlocpodLogSink`
- `BlocpodLogEncoder`
- `JsonLogEncoder`
- `PrettyLogEncoder`
- `PrettyLogDetail`
- `DebugPrintLogSink`
- `formatBlocpodLogEntry`

`blocpod_logger` may use Flutter's `debugPrint` for local-development output.
It must not import `blocpod_arch`. `DebugPrintLogSink` and
`formatBlocpodLogEntry` emit versioned JSON Lines by default. Pretty output is
opt-in.

## Usage

JSON is the default:

```dart
import 'package:blocpod_logger/blocpod_logger.dart';

final sink = DebugPrintLogSink();

sink.write(
  BlocpodLogEntry(
    level: BlocpodLogLevel.info,
    message: 'CounterController IncrementEvent state.transition#1 data->data',
    timestamp: DateTime.utc(2026, 8, 3, 12),
    sequence: 7,
    traceId: 'trace-1',
    spanId: 'span-2',
    attributes: const {
      'phase': 'state.transition',
      'transitionIndex': 1,
      'durationMicros': 1200,
    },
  ),
);
```

Example output:

```json
{"schema":"blocpod.log","schemaVersion":1,"timestamp":"2026-08-03T12:00:00.000Z","sequence":7,"level":"info","message":"CounterController IncrementEvent state.transition#1 data->data","trace":{"traceId":"trace-1","spanId":"span-2"},"attributes":{"phase":"state.transition","transitionIndex":1,"durationMicros":1200}}
```

To opt into pretty local output:

```dart
final sink = DebugPrintLogSink(
  encoder: const PrettyLogEncoder(
    detail: PrettyLogDetail.verbose,
  ),
);
```

Example output:

```text
12:00:00.000Z INFO  CounterController IncrementEvent state.transition#1 data->data
  sequence=7 trace=trace-1/span-2
  attributes={phase: state.transition, transitionIndex: 1, durationMicros: 1200}
```

## Migration notes

- `BlocpodLogEntry.metadata` was replaced by `attributes`.
- `sequence`, `traceId`, `spanId`, and `parentSpanId` are now dedicated fields.
- Blocpod no longer performs automatic key-based redaction. Applications own
  sensitive-data policy before writing to sinks or forwarding to external SDKs.

## External sink adapters

External logger adapters are application-owned boundary code. `blocpod_logger`
does not export a `UserProvidedLogSink` helper or a built-in Talker/Sentry
integration.

Minimal Talker adapter pseudocode:

```dart
final class TalkerLogSink implements BlocpodLogSink {
  TalkerLogSink(this.talker);

  final Talker talker;

  @override
  void write(BlocpodLogEntry entry) {
    talker.log(
      entry.message,
      logLevel: entry.level.name,
      time: entry.timestamp,
      exception: entry.error,
      stackTrace: entry.stackTrace,
      extras: <String, Object?>{
        if (entry.sequence != null) 'sequence': entry.sequence,
        if (entry.traceId != null) 'traceId': entry.traceId,
        if (entry.spanId != null) 'spanId': entry.spanId,
        if (entry.parentSpanId != null) 'parentSpanId': entry.parentSpanId,
        ...entry.attributes,
      },
    );
  }
}
```

That adapter owns field mapping, redaction, filtering, batching, and any
SDK-specific conventions.
