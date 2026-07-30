# Blocpod Initial State Established Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record the initial `AsyncValue` established by `EventControllerNotifier.build()` through the existing payload-free state summary hooks, without requiring controller changes in consuming applications.

**Architecture:** Add `EventLogPhase.initialStateEstablished` to the `blocpod_arch` public lifecycle contract and compose a one-shot logger callback ahead of Riverpod's `runBuild()` completion callback. The composed callback reads the final `AsyncValue`, reuses `stateLabel`, `stateMetadata`, `controllerMetadata`, and `EventLogRecord`, then calls Riverpod's original callback; it leaves transition-only fields empty. Update the bridge formatters exhaustively, then align public documentation and the two affected package versions at `0.2.0`.

**Tech Stack:** Dart 3.11.5, Flutter, resolved Riverpod/flutter_riverpod 3.4.2, `flutter_test`, Dart pub workspace

## Global Constraints

- Preserve the existing `controllerCreated`, dispatch, transition, completion, failure, and disposal emission timing and field semantics.
- Do not add, remove, or rename any `EventLogRecord` field.
- Keep `stateMetadata({required previous, required next})` source-compatible; for initialization pass the same final `AsyncValue<S>` as both arguments.
- Emit `initialStateEstablished` once per controller instance, after the first successful or failed `build()` completion; dependency invalidation must not emit it again.
- Populate `nextStateKind`, `nextStateLabel`, `stateMetadata`, and controller `metadata`; leave `eventName`, all previous-state fields, `hasChanged`, `duration`, and `transitionIndex` null.
- If the final state is `AsyncError`, copy its `error` and `stackTrace` into the record.
- Keep logging failure-isolated through `_writeRecordSafely`; logger and summary-hook failures must never change provider behavior.
- Do not start logging direct `state =` assignments outside an event dispatch.
- Keep `blocpod_arch` independent of `blocpod_logger`; only `blocpod_arch_logger` may know both packages.
- Use the log-facing label `state.established`.
- Treat the enum addition as the only source-breaking surface: bump `blocpod_arch` and `blocpod_arch_logger` to `0.2.0`, while leaving `blocpod_logger` at `0.1.1`.
- Do not publish packages, create or push tags, or push commits as part of this implementation. Those release actions require a separate explicit request.

---

## File Structure

- Modify `packages/arch/lib/src/event_log_record.dart`
  - Own the new public `EventLogPhase.initialStateEstablished` enum value.
- Modify `packages/arch/lib/src/event_controller.dart`
  - Register the build-completion callback and construct the one-shot initialization record.
- Modify `packages/arch/test/event_logging_test.dart`
  - Prove async success, async failure, default hooks, synchronous build, one-shot rebuild behavior, lifecycle ordering, failure isolation, and dispatch regression.
- Modify `packages/arch_logger/lib/src/event_log_record_formatter.dart`
  - Map the new phase to `state.established` and produce a compact event-free state message.
- Modify `packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart`
  - Render the initialized state, trace, controller metadata keys, and state metadata keys without exposing values.
- Modify `packages/arch_logger/test/blocpod_arch_logger_test.dart`
  - Lock compact/structured and pretty formatting for the new phase.
- Modify `packages/arch/pubspec.yaml`
  - Prepare `blocpod_arch 0.2.0`.
- Modify `packages/arch/CHANGELOG.md`
  - Document the new initialization record and enum compatibility impact.
- Modify `packages/arch_logger/pubspec.yaml`
  - Prepare `blocpod_arch_logger 0.2.0` and require `blocpod_arch ^0.2.0`.
- Modify `packages/arch_logger/CHANGELOG.md`
  - Document formatter support for `state.established`.
- Modify `packages/sample/pubspec.yaml`
  - Align the private sample with `blocpod_arch ^0.2.0` and `blocpod_arch_logger ^0.2.0`.
- Modify `README.md`
  - Include initial-state establishment in the workspace observability summary.
- Modify `packages/arch/README.md`
  - Document when `initialStateEstablished` is emitted and which summary hooks it uses.
- Modify `packages/arch_logger/README.md`
  - Include `state.established` in formatter labels and describe its event-free shape.
- Modify `docs/ARCHITECTURE.md`
  - Add initial state establishment to the controller lifecycle contract.
- Modify `docs/ARCHITECTURE-ko.md`
  - Keep the Korean architecture contract synchronized.
- Modify `docs/CONVENTIONS.md`
  - Add the new phase to controller logging conventions.

---

### Task 1: Add the one-shot core initialization record

**Files:**
- Modify: `packages/arch/test/event_logging_test.dart:54-195`
- Modify: `packages/arch/test/event_logging_test.dart:197-449`
- Modify: `packages/arch/lib/src/event_log_record.dart:6-10`
- Modify: `packages/arch/lib/src/event_controller.dart:16-26`
- Modify: `packages/arch/lib/src/event_controller.dart:115-170`

**Interfaces:**
- Consumes: Riverpod `WhenComplete`, represented by `void Function(void Function())?`, returned from `AsyncNotifier.runBuild()`.
- Produces: `EventLogPhase.initialStateEstablished`.
- Produces: exactly one `EventLogRecord` per controller instance with `phase: EventLogPhase.initialStateEstablished`.
- Produces: `_logInitialStateEstablishedOnce()` as a private, no-argument completion callback.

- [x] **Step 1: Add focused test controllers for failure, default hooks, synchronous build, and rebuild**

Add these declarations near the existing providers and test controllers in `packages/arch/test/event_logging_test.dart`:

```dart
final failingBuildProvider = AsyncNotifierProvider<FailingBuildController, int>(
  FailingBuildController.new,
  retry: (_, _) => null,
);

final plainSyncProvider = AsyncNotifierProvider<PlainSyncController, int>(
  PlainSyncController.new,
);

final rebuildingProvider = AsyncNotifierProvider<RebuildingController, int>(
  RebuildingController.new,
);

final class FailingBuildController extends EventControllerNotifier<int, LoggingEvent> {
  @override
  Future<int> build() async {
    throw StateError('restore failed');
  }

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}

final class PlainSyncController extends EventControllerNotifier<int, LoggingEvent> {
  @override
  int build() => 7;

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}

final class RebuildingController extends EventControllerNotifier<int, LoggingEvent> {
  int _buildCount = 0;

  @override
  int build() => ++_buildCount;

  @override
  Future<void> onEvent(LoggingEvent event) async {}
}
```

- [x] **Step 2: Write failing tests for async success and lifecycle field semantics**

Add this test before the existing dispatch tests:

```dart
test('async build logs its initialized state through existing summary hooks', () async {
  final logger = CollectingEventLogger();
  final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
  addTearDown(container.dispose);

  await container.read(loggingProvider.future);

  expect(logger.records.map((record) => record.phase), <EventLogPhase>[
    EventLogPhase.controllerCreated,
    EventLogPhase.initialStateEstablished,
  ]);
  final initialized = logger.records.singleWhere(
    (record) => record.phase == EventLogPhase.initialStateEstablished,
  );
  expect(initialized.controllerName, 'LoggingController');
  expect(initialized.eventName, isNull);
  expect(initialized.previousStateKind, isNull);
  expect(initialized.previousStateLabel, isNull);
  expect(initialized.nextStateKind, AsyncValueKind.data);
  expect(initialized.nextStateLabel, 'value:0');
  expect(initialized.hasChanged, isNull);
  expect(initialized.duration, isNull);
  expect(initialized.transitionIndex, isNull);
  expect(initialized.stateMetadata, <String, Object?>{
    'previousKind': 'data',
    'nextKind': 'data',
  });
  expect(initialized.metadata, containsPair('controllerScope', 'sample-logging'));
  expect(initialized.error, isNull);
  expect(initialized.stackTrace, isNull);
});
```

- [x] **Step 3: Write failing tests for error, default-hook, sync, and rebuild behavior**

Add these tests alongside the lifecycle tests:

```dart
test('failed async build logs the final AsyncError and stack trace', () async {
  final logger = CollectingEventLogger();
  final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
  addTearDown(container.dispose);

  await expectLater(
    container.read(failingBuildProvider.future),
    throwsA(isA<StateError>().having((error) => error.message, 'message', 'restore failed')),
  );

  final initialized = logger.records.singleWhere(
    (record) => record.phase == EventLogPhase.initialStateEstablished,
  );
  expect(initialized.nextStateKind, AsyncValueKind.error);
  expect(initialized.nextStateLabel, isNull);
  expect(
    initialized.error,
    isA<StateError>().having((error) => error.message, 'message', 'restore failed'),
  );
  expect(initialized.stackTrace, isNotNull);
});

test('sync build logs initialization even when state summary hooks are not overridden', () async {
  final logger = CollectingEventLogger();
  final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
  addTearDown(container.dispose);

  expect(await container.read(plainSyncProvider.future), 7);

  final initialized = logger.records.singleWhere(
    (record) => record.phase == EventLogPhase.initialStateEstablished,
  );
  expect(initialized.nextStateKind, AsyncValueKind.data);
  expect(initialized.nextStateLabel, isNull);
  expect(initialized.stateMetadata, isEmpty);
});

test('provider rebuild does not duplicate the initialized-state record', () async {
  final logger = CollectingEventLogger();
  final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
  addTearDown(container.dispose);

  final notifier = container.read(rebuildingProvider.notifier);
  expect(await container.read(rebuildingProvider.future), 1);

  container.invalidate(rebuildingProvider);

  expect(await container.read(rebuildingProvider.future), 2);
  expect(container.read(rebuildingProvider.notifier), same(notifier));
  expect(
    logger.records.where((record) => record.phase == EventLogPhase.initialStateEstablished),
    hasLength(1),
  );
});
```

- [x] **Step 4: Run the new tests to verify the public phase is missing**

Run:

```bash
cd packages/arch
flutter test test/event_logging_test.dart --plain-name 'async build logs its initialized state through existing summary hooks'
```

Expected: compilation fails because `EventLogPhase.initialStateEstablished` does not exist.

- [x] **Step 5: Add the public enum value in lifecycle order**

Change `EventLogPhase` in `packages/arch/lib/src/event_log_record.dart` to:

```dart
/// Observable lifecycle phase for a Blocpod controller.
enum EventLogPhase {
  controllerCreated,
  initialStateEstablished,
  eventStarted,
  transition,
  eventCompleted,
  eventFailed,
  controllerDisposed,
}
```

- [x] **Step 6: Run the focused test to verify record emission is still missing**

Run:

```bash
cd packages/arch
flutter test test/event_logging_test.dart --plain-name 'async build logs its initialized state through existing summary hooks'
```

Expected: test compiles and fails because the logger contains only `controllerCreated`.

- [x] **Step 7: Compose the completion callback while preserving Riverpod's returned callback**

Add the new flag and update `runBuild()` in `packages/arch/lib/src/event_controller.dart`:

```dart
bool _didLogControllerCreated = false;
bool _didLogInitialStateEstablished = false;
bool _didRegisterControllerDisposed = false;

@mustCallSuper
@override
void Function(void Function())? runBuild() {
  _logControllerCreatedOnce();
  _registerControllerDisposedOnce();
  final whenComplete = super.runBuild();
  return whenComplete == null
      ? null
      : (onComplete) {
          whenComplete(() {
            _logInitialStateEstablishedOnce();
            onComplete();
          });
        };
}
```

This verified Riverpod 3.4.2 composition preserves Riverpod's cancellation/completion behavior and its original callback ordering: a cancelled async build does not invoke the composed callback, while synchronous data and asynchronous data/error log the established state before Riverpod's original completion callback runs.

- [x] **Step 8: Construct the initialization record from the final state**

Add this method after `_logControllerCreatedOnce()`:

```dart
void _logInitialStateEstablishedOnce() {
  if (_didLogInitialStateEstablished) {
    return;
  }
  _didLogInitialStateEstablished = true;

  try {
    final initialized = state;
    final (error, stackTrace) = switch (initialized) {
      AsyncError<S>(:final error, :final stackTrace) => (error, stackTrace),
      _ => (null, null),
    };
    final startedAt = DateTime.now().toUtc();
    final traceContext = TraceContext.root(startedAt: startedAt);
    _writeRecordSafely(
      EventLogRecord(
        phase: EventLogPhase.initialStateEstablished,
        traceContext: traceContext,
        controllerName: _safeControllerName(),
        startedAt: startedAt,
        nextStateKind: asyncValueKindOf(initialized),
        nextStateLabel: _safeStateLabel(initialized),
        stateMetadata: _safeStateMetadata(
          previous: initialized,
          next: initialized,
        ),
        error: error,
        stackTrace: stackTrace,
        metadata: _safeControllerMetadata(),
      ),
    );
  } catch (_) {
    // Logging must never affect application flow.
  }
}
```

Do not populate transition-only or event-only fields. Do not change the state setter.

- [x] **Step 9: Extend hook documentation from transitions to state observations**

Update the two protected hook comments in `packages/arch/lib/src/event_controller.dart`:

```dart
/// Optional payload-free state label recorded for initialization and transitions.
```

and:

```dart
/// Optional payload-free state metadata recorded for initialization and transitions.
///
/// During initialization, [previous] and [next] are the same established state.
```

- [x] **Step 10: Run the core logging tests**

Run:

```bash
cd packages/arch
flutter test test/event_logging_test.dart
```

Expected: all tests pass, including the existing dispatch phase-order, error, trace, metadata snapshot, and logger-failure tests.

- [x] **Step 11: Commit the core contract**

```bash
git add packages/arch/lib/src/event_controller.dart packages/arch/lib/src/event_log_record.dart packages/arch/test/event_logging_test.dart
git commit -m "feat(arch)!: log initialized controller state"
```

---

### Task 2: Format `initialStateEstablished` in the logger bridge

**Files:**
- Modify: `packages/arch_logger/test/blocpod_arch_logger_test.dart:112-197`
- Modify: `packages/arch_logger/test/blocpod_arch_logger_test.dart:303-337`
- Modify: `packages/arch_logger/lib/src/event_log_record_formatter.dart:27-89`
- Modify: `packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart:40-90`

**Interfaces:**
- Consumes: `EventLogPhase.initialStateEstablished` and its event-free `EventLogRecord` shape from Task 1.
- Produces: `eventLogPhaseLabel(EventLogPhase.initialStateEstablished) == 'state.established'`.
- Produces: compact message `CounterController state.established ->data`.
- Produces: pretty output headed by `🔵 state.established -- CounterController`.

- [x] **Step 1: Add a test fixture with initialization field semantics**

Add this helper after `eventRecord()` in `packages/arch_logger/test/blocpod_arch_logger_test.dart`:

```dart
EventLogRecord establishedInitialStateRecord({
  Object? error,
  StackTrace? stackTrace,
}) {
  final startedAt = DateTime.utc(2026, 7, 30, 9, 30);
  return EventLogRecord(
    phase: EventLogPhase.initialStateEstablished,
    traceContext: TraceContext.root(startedAt: startedAt),
    controllerName: 'CounterController',
    startedAt: startedAt,
    nextStateKind: error == null ? AsyncValueKind.data : AsyncValueKind.error,
    nextStateLabel: error == null ? 'ready' : 'error',
    stateMetadata: const <String, Object?>{'status': 'ready'},
    error: error,
    stackTrace: stackTrace,
    metadata: const <String, Object?>{'feature': 'counter'},
  );
}
```

- [x] **Step 2: Add failing phase-label and compact formatter tests**

Extend the phase label test with:

```dart
expect(eventLogPhaseLabel(EventLogPhase.initialStateEstablished), 'state.established');
```

Add:

```dart
test('compact formatter maps initialized state without transition or event fields', () {
  const formatter = EventLogRecordFormatter();

  final entry = formatter.format(establishedInitialStateRecord());

  expect(entry.message, 'CounterController state.established ->data');
  expect(entry.metadata, containsPair('phase', 'state.established'));
  expect(entry.metadata, containsPair('controllerName', 'CounterController'));
  expect(entry.metadata, containsPair('nextStateKind', 'data'));
  expect(entry.metadata, containsPair('nextStateLabel', 'ready'));
  expect(entry.metadata, containsPair('stateMetadata', <String, Object?>{'status': 'ready'}));
  expect(entry.metadata.containsKey('eventName'), isFalse);
  expect(entry.metadata.containsKey('previousStateKind'), isFalse);
  expect(entry.metadata.containsKey('previousStateLabel'), isFalse);
  expect(entry.metadata.containsKey('hasChanged'), isFalse);
});
```

- [x] **Step 3: Add a failing pretty formatter test**

Add:

```dart
test('pretty formatter renders initialized state without inventing an event or previous state', () {
  const formatter = PrettyEventLogRecordFormatter();

  final entry = formatter.format(establishedInitialStateRecord());

  expect(entry.message, contains('🔵 state.established -- CounterController'));
  expect(entry.message, contains('next: data(ready)'));
  expect(entry.message, contains('metadataKeys: feature'));
  expect(entry.message, contains('stateMetadataKeys: status'));
  expect(entry.message, isNot(contains('Event:')));
  expect(entry.message, isNot(contains('previous:')));
  expect(entry.message, isNot(contains('feature=counter')));
  expect(entry.message, isNot(contains('status=ready')));
  expect(entry.metadata, containsPair('phase', 'state.established'));
});
```

- [x] **Step 4: Run the bridge tests to verify exhaustive switches fail**

Run:

```bash
cd packages/arch_logger
flutter test test/blocpod_arch_logger_test.dart
```

Expected: compilation fails because `eventLogPhaseLabel`, compact `_messageFor`, and pretty `_messageFor` do not handle `EventLogPhase.initialStateEstablished`.

- [x] **Step 5: Add the log-facing label and compact message**

Add this arm to `eventLogPhaseLabel()` in `packages/arch_logger/lib/src/event_log_record_formatter.dart`:

```dart
EventLogPhase.initialStateEstablished => 'state.established',
```

Add this arm immediately after `controllerCreated` in `EventLogRecordFormatter._messageFor()`:

```dart
EventLogPhase.initialStateEstablished => '${record.controllerName} $phaseLabel$states',
```

Do not insert an `unknownEvent` placeholder for this phase.

- [x] **Step 6: Add the pretty initialization renderer**

Add the new switch arm in `PrettyEventLogRecordFormatter._messageFor()`:

```dart
EventLogPhase.initialStateEstablished => _initialStateEstablishedMessage(record),
```

Add:

```dart
String _initialStateEstablishedMessage(EventLogRecord record) {
  final buffer = StringBuffer()
    ..writeln('🔵 state.established -- ${record.controllerName}')
    ..writeln('   next: ${_stateText(record.nextStateKind, record.nextStateLabel)}')
    ..write('   trace: ${record.traceContext.traceId}/${record.traceContext.spanId}');
  _appendMetadataLine(buffer, 'metadata', record.metadata);
  _appendMetadataLine(buffer, 'stateMetadata', record.stateMetadata);
  return buffer.toString();
}
```

This reuses the existing metadata-key filtering so sensitive keys and all values stay out of human-readable output.

- [x] **Step 7: Run bridge tests**

Run:

```bash
cd packages/arch_logger
flutter test test/blocpod_arch_logger_test.dart
```

Expected: all tests pass, including the existing reserved-metadata, sink-isolation, error-level, and transition formatting tests.

- [x] **Step 8: Commit bridge support**

```bash
git add packages/arch_logger/lib/src/event_log_record_formatter.dart packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart packages/arch_logger/test/blocpod_arch_logger_test.dart
git commit -m "feat(arch_logger)!: format initialized state logs"
```

---

### Task 3: Align package versions, changelogs, and public contracts

**Files:**
- Modify: `packages/arch/pubspec.yaml:1-4`
- Modify: `packages/arch/CHANGELOG.md:1-4`
- Modify: `packages/arch_logger/pubspec.yaml:1-20`
- Modify: `packages/arch_logger/CHANGELOG.md:1-4`
- Modify: `packages/sample/pubspec.yaml:11-17`
- Modify: `README.md:27-33`
- Modify: `packages/arch/README.md:65-68`
- Modify: `packages/arch_logger/README.md:36-65`
- Modify: `docs/ARCHITECTURE.md:38-45`
- Modify: `docs/ARCHITECTURE-ko.md:38-45`
- Modify: `docs/CONVENTIONS.md:24-31`

**Interfaces:**
- Consumes: the new public enum and formatter behavior from Tasks 1 and 2.
- Produces: release-ready `blocpod_arch 0.2.0`.
- Produces: release-ready `blocpod_arch_logger 0.2.0` with `blocpod_arch: ^0.2.0`.
- Produces: sample constraints compatible with both new packages.

- [x] **Step 1: Bump only the affected package versions and constraints**

Apply these exact version changes:

```yaml
# packages/arch/pubspec.yaml
version: 0.2.0
```

```yaml
# packages/arch_logger/pubspec.yaml
version: 0.2.0

dependencies:
  blocpod_arch: ^0.2.0
  blocpod_logger: ^0.1.1
```

```yaml
# packages/sample/pubspec.yaml
dependencies:
  blocpod_arch: ^0.2.0
  blocpod_arch_logger: ^0.2.0
  blocpod_logger: ^0.1.1
```

Do not change the workspace version or `blocpod_logger` version.

- [x] **Step 2: Add changelog entries**

Prepend to `packages/arch/CHANGELOG.md`:

```markdown
## 0.2.0

- Added `EventLogPhase.initialStateEstablished` for the initial `AsyncValue` established by `EventControllerNotifier.build()`.
- Initial-state records reuse sanitized state/controller summary hooks and include build errors without changing provider flow.
- This adds an enum value and requires exhaustive phase switches to handle `initialStateEstablished`.
```

Prepend to `packages/arch_logger/CHANGELOG.md`:

```markdown
## 0.2.0

- Added compact and pretty formatter support for `state.established` records.
- Raised the minimum `blocpod_arch` dependency to `^0.2.0`.
```

- [x] **Step 3: Update public documentation with one consistent lifecycle**

Use this lifecycle everywhere it is enumerated:

```text
controllerCreated → initialStateEstablished → eventStarted → transition* → eventCompleted | eventFailed → controllerDisposed
```

Document these semantics in the listed README and architecture/conventions files:

- `initialStateEstablished` is emitted once after the first sync/async build settles.
- It has no event or previous state.
- It invokes existing `stateLabel` and `stateMetadata`; initialization passes the final state as both `previous` and `next`.
- An `AsyncError` initialization carries `error` and `stackTrace`.
- Compact phase text is `state.established`.
- Direct non-dispatch assignments remain intentionally unobserved.

- [x] **Step 4: Resolve the workspace after version alignment**

Run:

```bash
flutter pub get
dart pub workspace list
```

Expected: dependency resolution succeeds and the workspace lists `arch`, `logger`, `arch_logger`, and `sample`.

- [x] **Step 5: Run format and static analysis**

Run:

```bash
dart format --line-length 120 packages/arch/lib packages/arch/test packages/arch_logger/lib packages/arch_logger/test
flutter analyze
```

Expected: formatter reports no unintended files after formatting completes; analyzer reports `No issues found!`.

- [x] **Step 6: Run every workspace package test suite**

Run:

```bash
(cd packages/arch && flutter test)
(cd packages/logger && flutter test)
(cd packages/arch_logger && flutter test)
(cd packages/sample && flutter test)
```

Expected: all four test suites pass. The sample suite proves that adding the startup record does not break existing dispatch/log-sink behavior.

- [x] **Step 7: Review the complete diff for scope and compatibility**

Run:

```bash
git diff --check
git diff --stat
git diff -- packages/arch packages/arch_logger packages/sample/pubspec.yaml README.md docs/ARCHITECTURE.md docs/ARCHITECTURE-ko.md docs/CONVENTIONS.md
```

Verify:

- No `EventLogRecord` fields changed.
- No protected hook signatures changed.
- No direct-state-assignment logging was added.
- No `blocpod_logger` source or version changed.
- No metadata value was added to pretty message text.
- Versions are exactly `blocpod_arch 0.2.0`, `blocpod_arch_logger 0.2.0`, and `blocpod_logger 0.1.1`.

- [x] **Step 8: Commit release preparation and documentation**

```bash
git add packages/arch/pubspec.yaml packages/arch/CHANGELOG.md packages/arch_logger/pubspec.yaml packages/arch_logger/CHANGELOG.md packages/sample/pubspec.yaml README.md packages/arch/README.md packages/arch_logger/README.md docs/ARCHITECTURE.md docs/ARCHITECTURE-ko.md docs/CONVENTIONS.md
git commit -m "chore: prepare initialized state logging release"
```

---

## Post-Implementation Release Gate

Publishing is deliberately outside the implementation tasks. After explicit release authorization:

1. Confirm `git status --short` is clean; pub.dev dry-runs are not reliable release evidence from a dirty checkout.
2. Run `dart pub publish --dry-run` in `packages/arch`.
3. Publish `blocpod_arch 0.2.0`.
4. Re-resolve and run `dart pub publish --dry-run` in `packages/arch_logger` only after hosted `blocpod_arch 0.2.0` is visible.
5. Publish `blocpod_arch_logger 0.2.0`.
6. Use package-scoped tags consistent with repository history, with separate tags for each published package.

## Post-Release Consumer Acceptance

In the 9.81 Park 3.0 checkout, update only the package dependency resolution needed to consume the release; do not modify `SessionController` logging hooks.

Verify a cold start that restores:

- an authenticated session, and
- an unauthenticated/guest session.

For each case, assert that the log stream contains `state.established` for `SessionController`, includes the existing sanitized `isAuthenticated` and `isGuest` metadata, and contains no raw session/token payload. Also force session restoration to fail and verify the established-state record has `nextStateKind: error`, `error`, and `stackTrace`, distinct from a legitimate unauthenticated state.
