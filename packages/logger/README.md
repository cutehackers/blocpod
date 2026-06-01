# blocpod_logger

Generic logging primitives for Blocpod.

This package owns:

- `BlocpodLogLevel`
- `BlocpodLogEntry`
- `BlocpodLogSink`
- `DebugPrintLogSink`
- `formatBlocpodLogEntry`

`blocpod_logger` may use Flutter's `debugPrint` for local-development output. It must not import `blocpod_arch`.
