# Blocpod

Blocpod is a Riverpod-based event architecture workspace for building BLoC-like clients without replacing Riverpod.

The workspace starts from the design in [docs/superpowers/specs/2026-06-01-blocpod-riverpod-event-architecture-design.md](docs/superpowers/specs/2026-06-01-blocpod-riverpod-event-architecture-design.md).

## Packages

- `packages/arch` (`blocpod_arch`): `Result`, `UseCase`, `EventControllerNotifier`, dispatch extensions, trace context, event records, and no-op event logger provider.
- `packages/logger` (`blocpod_logger`): generic log entries, log levels, log sinks, debug print output, and local-development formatting.
- `packages/arch_logger` (`blocpod_arch_logger`): `EventLogger` adapter that maps `EventLogRecord` values to `BlocpodLogEntry` values.

## Local Commands

```sh
flutter pub get
dart pub workspace list
(cd packages/arch && flutter test)
(cd packages/logger && flutter test)
(cd packages/arch_logger && flutter test)
flutter analyze
dart format --line-length 120 .
```

## Design Rules

- `blocpod_arch` must not depend on `blocpod_logger`.
- `blocpod_logger` must not depend on `blocpod_arch`.
- `blocpod_arch_logger` is the only package that knows both sides.
- Logger support is installed through sibling packages and provider overrides, not optional imports.
