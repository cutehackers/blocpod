# Changelog

## 0.2.0

- Changed `DebugPrintLogSink` and `formatBlocpodLogEntry` to emit versioned JSON Lines by default.
- Added `BlocpodLogEncoder`, `JsonLogEncoder`, `PrettyLogEncoder`, and `PrettyLogDetail`.
- Replaced `BlocpodLogEntry.metadata` with `attributes` and dedicated sequence/trace fields.
- Removed automatic key-based redaction; applications and external sink adapters now own sensitive-data policy.

## 0.1.1

- Co-released with `blocpod_arch 0.1.1`.

## 0.1.0

- Initial release of Blocpod's generic logging primitives.
- Added log levels, structured log entries, log sinks, debug-print output, and local-development formatting.
