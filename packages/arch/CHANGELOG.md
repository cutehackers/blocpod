# Changelog

## 0.1.1

- Upgraded `flutter_riverpod` dependency to `^3.3.2`.
- Updated `EventControllerNotifier.runBuild()` return type to match the new `WhenComplete` signature introduced in `riverpod 3.3.2`.

## 0.1.0

- Initial release of Blocpod's Riverpod event architecture primitives.
- Added `Result`, `UseCase`, event controller dispatch helpers, trace context, event log records, and no-op logger provider.
- Added payload-free controller lifecycle, event, transition, completion, and failure observability contracts.
