# Changelog

## 0.2.0

- Added `EventLogPhase.initialStateEstablished` for the initial `AsyncValue` established by `EventControllerNotifier.build()`.
- Initial-state records reuse sanitized state/controller summary hooks and include build errors without changing provider flow.
- This adds an enum value and requires exhaustive phase switches to handle `initialStateEstablished`.

## 0.1.1

- Upgraded `flutter_riverpod` dependency to `^3.3.2`.
- Updated `EventControllerNotifier.runBuild()` return type to match the new `WhenComplete` signature introduced in `riverpod 3.3.2`.

## 0.1.0

- Initial release of Blocpod's Riverpod event architecture primitives.
- Added `Result`, `UseCase`, event controller dispatch helpers, trace context, event log records, and no-op logger provider.
- Added payload-free controller lifecycle, event, transition, completion, and failure observability contracts.
