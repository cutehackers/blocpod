# Changelog

## Unreleased

- Added `occurredAt` and isolate-local `recordSequence` observation fields while
  keeping `startedAt` as span start and measuring dispatch duration
  monotonically.
- Isolated concurrent and nested dispatch completion with notifier-owned,
  event-local outcomes and closed-context attribution rules.
- Added synchronous, isolate-wide non-reentrant FIFO logger delivery with
  neutral callback context and per-record error isolation.

## 0.2.0

- Added `EventLogPhase.initialStateEstablished` for the initial `AsyncValue` established by `EventControllerNotifier.build()`.
- Initial-state records reuse sanitized state/controller summary hooks, include synchronous and asynchronous terminal build errors, and ignore canceled or intermediate retry-loading states without changing provider flow.
- Clarified that `controllerDisposed` is the first registered Riverpod ref disposal signal and may precede a rebuild on the same notifier.
- Upgraded `flutter_riverpod` to `^3.4.2` and aligned this package's minimum Dart SDK with Riverpod 3.4 at `^3.12.0`.
- This adds an enum value and requires exhaustive phase switches to handle `initialStateEstablished`.

## 0.1.1

- Upgraded `flutter_riverpod` dependency to `^3.3.2`.
- Updated `EventControllerNotifier.runBuild()` return type to match the new `WhenComplete` signature introduced in `riverpod 3.3.2`.

## 0.1.0

- Initial release of Blocpod's Riverpod event architecture primitives.
- Added `Result`, `UseCase`, event controller dispatch helpers, trace context, event log records, and no-op logger provider.
- Added payload-free controller lifecycle, event, transition, completion, and failure observability contracts.
