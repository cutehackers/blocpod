# Blocpod

Blocpod is a Riverpod-based event architecture workspace for building BLoC-like clients without replacing Riverpod.

The workspace starts from the design in [docs/design/blocpod-riverpod-event-architecture-design.md](docs/design/blocpod-riverpod-event-architecture-design.md).

## Packages

- `packages/arch` (`blocpod_arch`): event-controller, clean-architecture, trace, and event-logger contracts.
- `packages/logger` (`blocpod_logger`): generic log sink primitives and development logging output.
- `packages/arch_logger` (`blocpod_arch_logger`): bridge adapter from `blocpod_arch` event records to `blocpod_logger` sinks.

## Local Commands

```sh
flutter pub get
dart pub workspace list
flutter analyze
```

## Design Rules

- `blocpod_arch` must not depend on `blocpod_logger`.
- `blocpod_logger` must not depend on `blocpod_arch`.
- `blocpod_arch_logger` is the only package that knows both sides.
- Logger support is installed through sibling packages and provider overrides, not optional imports.
