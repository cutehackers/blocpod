# blocpod_logger

Generic logging primitives for Blocpod.

This package owns:

- `BlocpodLogLevel`
- `BlocpodLogEntry`
- `BlocpodLogSink`
- `DebugPrintLogSink`
- `formatBlocpodLogEntry`

`blocpod_logger` may use Flutter's `debugPrint` for local-development output. It must not import `blocpod_arch`.

## Usage

```dart
import 'package:blocpod_logger/blocpod_logger.dart';

final sink = DebugPrintLogSink();

sink.write(
  BlocpodLogEntry(
    level: BlocpodLogLevel.info,
    message: 'CounterController IncrementEvent state.transition#1 data->data',
    timestamp: DateTime.now().toUtc(),
    metadata: const {
      'phase': 'state.transition',
      'traceId': 'trace-1',
      'transitionIndex': 1,
      'durationMicros': 1200,
    },
  ),
);
```

`formatBlocpodLogEntry` redacts sensitive metadata keys such as tokens, secrets,
credentials, and passwords before printing. Error entries include the associated
error and stack trace when provided.
