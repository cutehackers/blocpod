# Blocpod

Blocpod is a Riverpod-based event architecture workspace for building BLoC-like clients without replacing Riverpod.

The workspace starts from the design in [docs/superpowers/specs/2026-06-01-blocpod-riverpod-event-architecture-design.md](docs/superpowers/specs/2026-06-01-blocpod-riverpod-event-architecture-design.md).

## Packages

- `packages/arch` (`blocpod_arch`): `Result`, `UseCase`, `EventControllerNotifier`, dispatch extensions, trace context, observer records, and no-op event logger provider.
- `packages/logger` (`blocpod_logger`): generic structured log entries, sinks, versioned JSON Lines by default, and opt-in pretty encoders.
- `packages/arch_logger` (`blocpod_arch_logger`): `EventLogger` adapter that maps `EventLogRecord` values to `BlocpodLogEntry` values with dedicated sequence/trace fields and nested event/state attributes.
- `packages/sample` (`blocpod_sample`): private runnable app that consumes the published `blocpod_*` packages and shows pretty event messages in-app.

## Local Commands

```sh
flutter pub get
dart pub workspace list
(cd packages/arch && flutter test)
(cd packages/logger && flutter test)
(cd packages/arch_logger && flutter test)
(cd packages/sample && flutter test)
flutter analyze
dart format --line-length 120 .
```

## Design Rules

- `blocpod_arch` must not depend on `blocpod_logger`.
- `blocpod_logger` must not depend on `blocpod_arch`.
- `blocpod_arch_logger` is the only package that knows both sides.
- Logger support is installed through sibling packages and provider overrides, not optional imports.
- JSON log output is the default; pretty formatting is an application opt-in.
- Applications own sink adapters, forwarding policy, and any redaction or filtering before logs leave Blocpod.
- Controller build/dispatch observability is payload-free by default and follows `controllerCreated → initialStateEstablished → eventStarted → transition* → eventCompleted | eventFailed`.
- `initialStateEstablished` is emitted once for the first terminal, non-loading build state. It ignores canceled builds and intermediate retry loading states, has no event or previous state, reuses sanitized `stateLabel` and `stateMetadata` (with the final state as both `previous` and `next`), and carries `error` and `stackTrace` for synchronous or asynchronous terminal errors.
- `controllerDisposed` records the first Riverpod ref disposal signal registered by the controller. Provider invalidation may emit it before a rebuild on the same notifier, so it is not proof that the notifier instance was destroyed.
- Direct `state = ...` assignments outside `dispatch` remain intentionally unobserved.
