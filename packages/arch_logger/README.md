# blocpod_arch_logger

Bridge adapter between `blocpod_arch` event records and `blocpod_logger` sinks.

This package owns:

- `EventLogRecordFormatter`
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
