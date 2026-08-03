# Blocpod Sample

This private Flutter package demonstrates the published Blocpod packages:

- `blocpod_arch`: event controllers, dispatch helpers, use cases, results, trace context, and event records.
- `blocpod_logger`: generic structured log entries, sinks, JSON default output, and pretty encoders.
- `blocpod_arch_logger`: adapter from event records to log entries, with formatter and sink choices owned by the app boundary.

The sample app installs `BlocpodEventLogger` with
`PrettyEventLogRecordFormatter`, so the on-screen event log shows readable
messages while the stored entries still keep structured `attributes`.

Visible output looks like:

```text
🔵 SampleCounterController established data(count:0)
🟡 SampleCounterController · CounterIncremented started from data(count:0)
✨ SampleCounterController · CounterIncremented transition[1] data(count:0) → data(count:1)
✅ SampleCounterController · CounterIncremented completed data(count:0) → data(count:1) in 1ms
```

Run it with:

```sh
cd packages/sample
flutter run -d chrome
```

Run tests with:

```sh
cd packages/sample
flutter test
```
