# blocpod_arch

Core Riverpod event architecture package for Blocpod.

This package owns:

- `EventController`
- `EventControllerNotifier`
- `ref.dispatch(...)` extensions
- `Result<T>` and `UseCase`
- trace and event logging contracts

It must not depend on `blocpod_logger` or any concrete logger package.
