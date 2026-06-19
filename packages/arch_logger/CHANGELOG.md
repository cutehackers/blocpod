# Changelog

## 0.1.3

- Raised the minimum `blocpod_arch` and `blocpod_logger` dependency constraints to `^0.1.1`.

## 0.1.2

- Added `BlocpodEventLogFormatter` so `BlocpodEventLogger` can use custom formatters.
- Added `PrettyEventLogRecordFormatter` for local transition debugging.
- Changed formatted phase metadata and compact messages to log-friendly labels such as `event.started`, `state.transition`, and `event.completed`.
- Pretty formatter messages now show metadata key summaries only; metadata values remain structured for sink-level handling.

## 0.1.1

- Co-released with `blocpod_arch 0.1.1`.

## 0.1.0

- Initial release of Blocpod's event-log bridge package.
- Added `BlocpodEventLogger` for converting `blocpod_arch` event records into `blocpod_logger` entries.
- Added event log formatting for phases, trace/span ids, event names, transition indexes, state summaries, durations, errors, and stack traces.
