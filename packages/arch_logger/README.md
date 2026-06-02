# blocpod_arch_logger

Bridge adapter between `blocpod_arch` event records and `blocpod_logger` sinks.

This package owns:

- `EventLogRecordFormatter`
- `BlocpodEventLogger`

`blocpod_arch_logger` is the only package in this workspace that should depend on both `blocpod_arch` and `blocpod_logger`.
