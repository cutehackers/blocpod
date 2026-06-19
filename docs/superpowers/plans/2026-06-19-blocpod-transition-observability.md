# Blocpod Transition Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve Blocpod state-transition observability without adding a BLoC-style `onChange` phase.

**Architecture:** Keep `EventLogPhase.transition` as the single event-attributed state-assignment record. Clarify its semantics in docs, expose a formatter interface so multiple formatter styles can be used by `BlocpodEventLogger`, and add a pretty formatter that renders Blocpod transition records in a BLoC-observer-like view without duplicating core records.

**Tech Stack:** Dart 3.11, Flutter, Riverpod `AsyncNotifier`, `flutter_test`, workspace packages `blocpod_arch`, `blocpod_logger`, and `blocpod_arch_logger`.

---

## Fixed Direction

Blocpod will not add `onChange`, `change`, or `stateChanged` as a new core phase in this slice.

The implementation must preserve the current record lifecycle:

```text
controllerCreated
eventStarted
transition
eventCompleted
eventFailed
controllerDisposed
```

`transition` remains the source of truth for state changes during `dispatch`. Its meaning is:

```text
An event-attributed state assignment observed while a Blocpod dispatch context is active.
```

This differs from BLoC:

```text
BLoC onTransition = event + currentState + nextState
BLoC onChange = currentState + nextState for BlocBase emit
Blocpod transition = event + AsyncValue previous/next kind + optional safe labels/metadata + trace/span context
```

## File Structure

- Modify `packages/arch_logger/lib/src/event_log_record_formatter.dart`
  - Add formatter interface.
  - Keep compact formatter structured.
  - Keep `hasChanged` as the user-facing state-change field.
  - Render phase values with log-friendly labels such as `controller.created`, `event.started`, and `state.transition` instead of enum camelCase names such as `controllerCreated`.
- Create `packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart`
  - Render multi-line local-development messages from `EventLogRecord`.
  - Derive BLoC-observer-like transition text from one Blocpod `transition` record.
  - Never print raw state payloads.
  - Never embed metadata values into the pretty message; render metadata key summaries only and keep values in structured metadata for sink-level redaction/indexing.
- Modify `packages/arch_logger/lib/src/blocpod_event_logger.dart`
  - Depend on formatter interface instead of concrete compact formatter.
- Modify `packages/arch_logger/lib/blocpod_arch_logger.dart`
  - Export the pretty formatter.
- Modify `packages/arch_logger/test/blocpod_arch_logger_test.dart`
  - Cover formatter interface compatibility.
  - Cover compact phase labels.
  - Cover pretty transition output.
  - Cover redaction in pretty output.
- Modify `packages/arch_logger/README.md`
  - Document compact vs pretty output.
- Modify `packages/logger/README.md`
  - Keep the generic log entry example aligned with `state.transition` labels.
- Modify `packages/sample/test/app_smoke_test.dart` and `packages/sample/test/logging_test.dart`
  - Keep sample-visible log assertions aligned with `event.completed`.
- Modify `docs/ARCHITECTURE.md` and `docs/ARCHITECTURE-ko.md`
  - Document why Blocpod does not add `onChange`.
  - Define `transition` as the canonical Blocpod state-assignment observation.

## Task 1: Add Formatter Interface

**Files:**
- Modify: `packages/arch_logger/lib/src/event_log_record_formatter.dart`
- Modify: `packages/arch_logger/lib/src/blocpod_event_logger.dart`
- Test: `packages/arch_logger/test/blocpod_arch_logger_test.dart`

- [ ] **Step 1: Write the failing interface compatibility test**

Add this test inside the existing `group('BlocpodEventLogger', () { ... })` in `packages/arch_logger/test/blocpod_arch_logger_test.dart`:

```dart
    test('accepts any Blocpod event log formatter implementation', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink, formatter: const StubEventLogFormatter());

      logger.log(eventRecord());

      expect(sink.entries, hasLength(1));
      expect(sink.entries.single.message, 'stub formatted');
      expect(sink.entries.single.metadata, containsPair('formatter', 'stub'));
    });
```

Add this helper class near the existing test helper classes:

```dart
final class StubEventLogFormatter implements BlocpodEventLogFormatter {
  const StubEventLogFormatter();

  @override
  BlocpodLogEntry format(EventLogRecord record) {
    return BlocpodLogEntry(
      level: BlocpodLogLevel.info,
      message: 'stub formatted',
      timestamp: record.startedAt,
      metadata: const <String, Object?>{'formatter': 'stub'},
    );
  }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
cd packages/arch_logger && flutter test test/blocpod_arch_logger_test.dart
```

Expected: FAIL because `BlocpodEventLogFormatter` is not defined and `BlocpodEventLogger.formatter` only accepts `EventLogRecordFormatter`.

- [ ] **Step 3: Add the formatter interface**

In `packages/arch_logger/lib/src/event_log_record_formatter.dart`, add this interface above `EventLogRecordFormatter`:

```dart
/// Converts Blocpod architecture event records into generic log entries.
abstract interface class BlocpodEventLogFormatter {
  /// Formats [record].
  BlocpodLogEntry format(EventLogRecord record);
}
```

Change the class declaration from:

```dart
final class EventLogRecordFormatter {
```

to:

```dart
final class EventLogRecordFormatter implements BlocpodEventLogFormatter {
```

Keep the existing `format` method body unchanged in this task.

- [ ] **Step 4: Update `BlocpodEventLogger` to accept the interface**

In `packages/arch_logger/lib/src/blocpod_event_logger.dart`, change:

```dart
  final EventLogRecordFormatter formatter;
```

to:

```dart
  final BlocpodEventLogFormatter formatter;
```

The constructor default stays:

```dart
  const BlocpodEventLogger(this.sink, {this.formatter = const EventLogRecordFormatter()});
```

- [ ] **Step 5: Run the focused test and verify it passes**

Run:

```bash
cd packages/arch_logger && flutter test test/blocpod_arch_logger_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/arch_logger/lib/src/event_log_record_formatter.dart packages/arch_logger/lib/src/blocpod_event_logger.dart packages/arch_logger/test/blocpod_arch_logger_test.dart
git commit -m "refactor: generalize blocpod event log formatter"
```

## Task 2: Add Log-Friendly Phase Labels

**Files:**
- Modify: `packages/arch_logger/lib/src/event_log_record_formatter.dart`
- Test: `packages/arch_logger/test/blocpod_arch_logger_test.dart`

- [ ] **Step 1: Write the failing compact phase label test**

Add this test inside `group('BlocpodEventLogger', () { ... })`:

```dart
    test('compact formatter uses log-friendly phase labels and keeps hasChanged', () {
      final sink = MemoryLogSink();
      final logger = BlocpodEventLogger(sink);
      final record = eventRecord(
        phase: EventLogPhase.transition,
        duration: null,
        transitionIndex: 1,
        previousStateLabel: 'count:0',
        nextStateLabel: 'count:1',
        stateMetadata: const <String, Object?>{'changedBy': 1},
      );

      logger.log(record);

      final entry = sink.entries.single;
      expect(entry.message, 'CounterController IncrementEvent state.transition#1 loading->data');
      final metadata = sink.entries.single.metadata;
      expect(metadata, containsPair('hasChanged', true));
      expect(metadata, containsPair('phase', 'state.transition'));
      expect(metadata, containsPair('previousStateLabel', 'count:0'));
      expect(metadata, containsPair('nextStateLabel', 'count:1'));
      expect(metadata, containsPair('stateMetadata', <String, Object?>{'changedBy': 1}));
    });
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
cd packages/arch_logger && flutter test test/blocpod_arch_logger_test.dart
```

Expected: FAIL because the compact formatter currently emits `phase: transition` and message text `transition#1`, not the log-friendly label `state.transition`.

- [ ] **Step 3: Add a phase label helper**

In `packages/arch_logger/lib/src/event_log_record_formatter.dart`, add this helper below `_reservedMetadataKeys`:

```dart
String eventLogPhaseLabel(EventLogPhase phase) {
  return switch (phase) {
    EventLogPhase.controllerCreated => 'controller.created',
    EventLogPhase.eventStarted => 'event.started',
    EventLogPhase.transition => 'state.transition',
    EventLogPhase.eventCompleted => 'event.completed',
    EventLogPhase.eventFailed => 'event.failed',
    EventLogPhase.controllerDisposed => 'controller.disposed',
  };
}
```

In `EventLogRecordFormatter.format`, change:

```dart
        'phase': record.phase.name,
```

to:

```dart
        'phase': eventLogPhaseLabel(record.phase),
```

In `_messageFor`, use `eventLogPhaseLabel(record.phase)` instead of literal camelCase phase words:

```dart
  String _messageFor(EventLogRecord record) {
    final eventName = record.eventName;
    final states = _statesFor(record);
    final duration = record.duration;
    final durationText = duration == null ? '' : ' ${duration.inMilliseconds}ms';
    final phaseLabel = eventLogPhaseLabel(record.phase);

    return switch (record.phase) {
      EventLogPhase.controllerCreated => '${record.controllerName} $phaseLabel',
      EventLogPhase.controllerDisposed => '${record.controllerName} $phaseLabel',
      EventLogPhase.eventStarted => '${record.controllerName} ${eventName ?? 'unknownEvent'} $phaseLabel$states',
      EventLogPhase.transition =>
        '${record.controllerName} ${eventName ?? 'unknownEvent'} $phaseLabel#${record.transitionIndex ?? 0}$states',
      EventLogPhase.eventCompleted =>
        '${record.controllerName} ${eventName ?? 'unknownEvent'} $phaseLabel$states$durationText',
      EventLogPhase.eventFailed =>
        '${record.controllerName} ${eventName ?? 'unknownEvent'} $phaseLabel$states$durationText',
    };
  }
```

Keep `hasChanged` as the state-change field.

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
cd packages/arch_logger && flutter test test/blocpod_arch_logger_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/arch_logger/lib/src/event_log_record_formatter.dart packages/arch_logger/test/blocpod_arch_logger_test.dart
git commit -m "feat: add readable blocpod phase labels"
```

## Task 3: Add Pretty Formatter

**Files:**
- Create: `packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart`
- Modify: `packages/arch_logger/lib/blocpod_arch_logger.dart`
- Test: `packages/arch_logger/test/blocpod_arch_logger_test.dart`

- [ ] **Step 1: Write the failing pretty transition test**

Add this test inside `group('BlocpodEventLogger', () { ... })`:

```dart
    test('pretty formatter renders transition as the canonical Blocpod state-assignment observation', () {
      final formatter = PrettyEventLogRecordFormatter();
      final record = eventRecord(
        phase: EventLogPhase.transition,
        duration: null,
        transitionIndex: 1,
        previousStateLabel: 'count:0',
        nextStateLabel: 'count:1',
        stateMetadata: const <String, Object?>{'changedBy': 1},
        metadata: const <String, Object?>{'amount': 1},
      );

      final entry = formatter.format(record);

      expect(entry.level, BlocpodLogLevel.info);
      expect(entry.message, contains('✨ state.transition -- CounterController'));
      expect(entry.message, contains('Event: IncrementEvent'));
      expect(entry.message, contains('previous: loading(count:0)'));
      expect(entry.message, contains('next: data(count:1)'));
      expect(entry.message, contains('transitionIndex: 1'));
      expect(entry.message, contains('hasChanged: true'));
      expect(entry.message, contains('eventMetadataKeys: amount'));
      expect(entry.message, contains('stateMetadataKeys: changedBy'));
      expect(entry.message, isNot(contains('amount=1')));
      expect(entry.message, isNot(contains('changedBy=1')));
      expect(entry.message, isNot(contains('onChange')));
      expect(entry.metadata, containsPair('phase', 'state.transition'));
      expect(entry.metadata, containsPair('hasChanged', true));
    });
```

Add this import to the test file if the public barrel is not enough after export:

```dart
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
```

The file already imports this barrel, so no extra import should be needed after the export step.

- [ ] **Step 2: Write the failing pretty redaction test**

Add this test inside `group('BlocpodEventLogger', () { ... })`:

```dart
    test('pretty formatter does not embed metadata values in messages', () {
      final formatter = PrettyEventLogRecordFormatter();
      final record = eventRecord(
        phase: EventLogPhase.transition,
        duration: null,
        transitionIndex: 1,
        previousStateLabel: 'ready',
        nextStateLabel: 'saving',
        metadata: const <String, Object?>{
          'customerEmail': 'user@example.com',
          'emailLength': 16,
          'token': 'abc',
          'secretKey': 'hidden',
          'credentialId': 'cred',
          'password': 'pw',
          'nested': <String, Object?>{
            'safe': 'visible',
            'token': 'nested-token',
          },
        },
        stateMetadata: const <String, Object?>{
          'status': 'saving',
          'password': 'state-password',
        },
      );

      final message = formatter.format(record).message;

      expect(message, contains('eventMetadataKeys: customerEmail,emailLength,nested'));
      expect(message, contains('stateMetadataKeys: status'));
      expect(message, isNot(contains('user@example.com')));
      expect(message, isNot(contains('emailLength=16')));
      expect(message, isNot(contains('nested={safe: visible}')));
      expect(message, isNot(contains('status=saving')));
      expect(message, isNot(contains('abc')));
      expect(message, isNot(contains('hidden')));
      expect(message, isNot(contains('cred')));
      expect(message, isNot(contains('pw')));
      expect(message, isNot(contains('nested-token')));
      expect(message, isNot(contains('state-password')));
    });
```

- [ ] **Step 3: Run the focused test and verify it fails**

Run:

```bash
cd packages/arch_logger && flutter test test/blocpod_arch_logger_test.dart
```

Expected: FAIL because `PrettyEventLogRecordFormatter` is not defined.

- [ ] **Step 4: Create the pretty formatter**

Create `packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart` with:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';

import 'event_log_record_formatter.dart';

const Set<String> _prettyReservedMetadataKeys = <String>{
  'phase',
  'traceId',
  'spanId',
  'parentSpanId',
  'controllerName',
  'eventName',
  'durationMicros',
  'transitionIndex',
  'previousStateKind',
  'nextStateKind',
  'hasChanged',
  'previousStateLabel',
  'nextStateLabel',
  'stateMetadata',
};

/// Formats Blocpod records for local, human-readable transition debugging.
final class PrettyEventLogRecordFormatter implements BlocpodEventLogFormatter {
  const PrettyEventLogRecordFormatter();

  @override
  BlocpodLogEntry format(EventLogRecord record) {
    final compact = const EventLogRecordFormatter().format(record);
    return BlocpodLogEntry(
      level: compact.level,
      message: _messageFor(record),
      timestamp: compact.timestamp,
      metadata: compact.metadata,
      error: compact.error,
      stackTrace: compact.stackTrace,
    );
  }

  String _messageFor(EventLogRecord record) {
    return switch (record.phase) {
      EventLogPhase.controllerCreated => _lifecycleMessage('🟢 controller.created', record),
      EventLogPhase.controllerDisposed => _lifecycleMessage('⚪ controller.disposed', record),
      EventLogPhase.eventStarted => _eventStartedMessage(record),
      EventLogPhase.transition => _transitionMessage(record),
      EventLogPhase.eventCompleted => _eventFinishedMessage('✅ event.completed', record),
      EventLogPhase.eventFailed => _eventFinishedMessage('🔴 event.failed', record),
    };
  }

  String _lifecycleMessage(String title, EventLogRecord record) {
    final buffer = StringBuffer()
      ..writeln('$title -- ${record.controllerName}')
      ..write('   trace: ${record.traceContext.traceId}/${record.traceContext.spanId}');
    _appendMetadataLine(buffer, 'metadata', record.metadata);
    return buffer.toString();
  }

  String _eventStartedMessage(EventLogRecord record) {
    final buffer = StringBuffer()
      ..writeln('🟡 event.started -- ${record.controllerName}, Event: ${record.eventName ?? 'unknownEvent'}')
      ..writeln('   previous: ${_stateText(record.previousStateKind, record.previousStateLabel)}')
      ..write('   trace: ${record.traceContext.traceId}/${record.traceContext.spanId}');
    _appendMetadataLine(buffer, 'eventMetadata', record.metadata);
    return buffer.toString();
  }

  String _transitionMessage(EventLogRecord record) {
    final buffer = StringBuffer()
      ..writeln('✨ state.transition -- ${record.controllerName}, Event: ${record.eventName ?? 'unknownEvent'}')
      ..writeln('   previous: ${_stateText(record.previousStateKind, record.previousStateLabel)}')
      ..writeln('   next: ${_stateText(record.nextStateKind, record.nextStateLabel)}')
      ..writeln('   transitionIndex: ${record.transitionIndex ?? 0}')
      ..write('   hasChanged: ${record.hasChanged ?? false}');
    _appendMetadataLine(buffer, 'eventMetadata', record.metadata);
    _appendMetadataLine(buffer, 'stateMetadata', record.stateMetadata);
    return buffer.toString();
  }

  String _eventFinishedMessage(String title, EventLogRecord record) {
    final durationText = record.duration == null ? 'unknown' : '${record.duration!.inMilliseconds}ms';
    final buffer = StringBuffer()
      ..writeln('$title -- ${record.controllerName}, Event: ${record.eventName ?? 'unknownEvent'}')
      ..writeln('   previous: ${_stateText(record.previousStateKind, record.previousStateLabel)}')
      ..writeln('   next: ${_stateText(record.nextStateKind, record.nextStateLabel)}')
      ..write('   duration: $durationText');
    _appendMetadataLine(buffer, 'eventMetadata', record.metadata);
    _appendMetadataLine(buffer, 'stateMetadata', record.stateMetadata);
    return buffer.toString();
  }

  String _stateText(AsyncValueKind? kind, String? label) {
    final kindText = kind?.name ?? 'unknown';
    if (label == null || label.isEmpty) {
      return kindText;
    }
    return '$kindText($label)';
  }

  void _appendMetadataLine(StringBuffer buffer, String label, Map<String, Object?> metadata) {
    final keys = _safeMetadataKeys(metadata);
    if (keys.isEmpty) {
      return;
    }
    buffer
      ..writeln()
      ..write('   ${label}Keys: ${keys.join(',')}');
  }

  List<String> _safeMetadataKeys(Map<String, Object?> metadata) {
    final keys = <String>[];
    for (final MapEntry(:key, :value) in metadata.entries) {
      if (_prettyReservedMetadataKeys.contains(key) || _isSensitiveKey(key)) {
        continue;
      }
      keys.add(key);
    }
    return keys;
  }

  bool _isSensitiveKey(Object? key) {
    final normalized = key.toString().toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('credential') ||
        normalized.contains('password');
  }
}
```

- [ ] **Step 5: Export the pretty formatter**

In `packages/arch_logger/lib/blocpod_arch_logger.dart`, add:

```dart
export 'src/pretty_event_log_record_formatter.dart';
```

- [ ] **Step 6: Run the focused test and verify it passes**

Run:

```bash
cd packages/arch_logger && flutter test test/blocpod_arch_logger_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart packages/arch_logger/lib/blocpod_arch_logger.dart packages/arch_logger/test/blocpod_arch_logger_test.dart
git commit -m "feat: add pretty blocpod transition formatter"
```

## Task 4: Document Transition Semantics

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/ARCHITECTURE-ko.md`
- Modify: `packages/arch_logger/README.md`
- Modify: `packages/logger/README.md`

- [ ] **Step 1: Update English architecture logging boundary**

In `docs/ARCHITECTURE.md`, replace the existing logging boundary bullet:

```markdown
- `transition` is emitted before each `state = ...` assignment while an event dispatch context is active.
```

with:

```markdown
- `transition` is emitted before each `state = ...` assignment while an event dispatch context is active. This is Blocpod's canonical state-assignment observation: it carries the event name, trace/span ids, previous/next `AsyncValue` kinds, optional sanitized state labels/metadata, and `hasChanged` information.
```

After the observer stream bullet list, add:

```markdown
Blocpod intentionally does not emit a separate BLoC-style `onChange` phase. BLoC's `onChange` observes `BlocBase.emit` with only current and next state, while Blocpod's `transition` observes Riverpod `AsyncValue` state assignments inside dispatch and keeps the event attribution. Human-readable formatters may render a transition in a BLoC-observer-like style, but the core record stream stays single-source and avoids duplicate state-change records.
```

- [ ] **Step 2: Update Korean architecture logging boundary**

In `docs/ARCHITECTURE-ko.md`, replace the matching Korean `transition` bullet with:

```markdown
- `transition`은 event dispatch context가 활성화된 동안 각 `state = ...` assignment 직전에 기록된다. 이것은 Blocpod의 표준 상태 assignment 관찰 단위이며 event name, trace/span id, previous/next `AsyncValue` kind, 선택적 sanitized state label/metadata, `hasChanged` 정보를 함께 담는다.
```

After the observer stream bullet list, add:

```markdown
Blocpod은 별도의 BLoC-style `onChange` phase를 의도적으로 추가하지 않는다. BLoC의 `onChange`는 current/next state만 가진 `BlocBase.emit` 관찰이고, Blocpod의 `transition`은 dispatch 내부의 Riverpod `AsyncValue` state assignment를 event attribution과 함께 관찰한다. 사람이 읽기 쉬운 formatter는 transition을 BLoC observer와 비슷한 형태로 렌더링할 수 있지만, core record stream은 중복 state-change record 없이 단일 source를 유지한다.
```

- [ ] **Step 3: Document compact and pretty logger usage**

In `packages/arch_logger/README.md`, add this section after the existing usage example:

````markdown
## Formatter Styles

The default `EventLogRecordFormatter` is compact and structured. It is best for log sinks that index metadata:

```dart
eventLoggerProvider.overrideWithValue(
  BlocpodEventLogger(DebugPrintLogSink()),
);
```

For local debugging, use `PrettyEventLogRecordFormatter`:

```dart
eventLoggerProvider.overrideWithValue(
  BlocpodEventLogger(
    DebugPrintLogSink(),
    formatter: const PrettyEventLogRecordFormatter(),
  ),
);
```

Blocpod does not emit a separate BLoC-style `onChange` phase. `transition` is the canonical event-attributed state-assignment record. Pretty output renders the same transition record in a human-readable form instead of duplicating the core record stream.
Pretty messages show metadata key summaries only; metadata values remain in `BlocpodLogEntry.metadata` for sink-level redaction and indexing.
````

Also update `packages/logger/README.md` examples to use `state.transition` for transition message and metadata phase examples.

- [ ] **Step 4: Run documentation grep checks**

Run:

```bash
rg -n "onChange|PrettyEventLogRecordFormatter|canonical state-assignment|표준 상태 assignment" docs/ARCHITECTURE.md docs/ARCHITECTURE-ko.md packages/arch_logger/README.md
```

Expected: output includes the new English docs, Korean docs, README formatter usage, and no stale `phase: transition` example in logger docs.

- [ ] **Step 5: Commit**

```bash
git add docs/ARCHITECTURE.md docs/ARCHITECTURE-ko.md packages/arch_logger/README.md packages/logger/README.md
git commit -m "docs: clarify blocpod transition observability"
```

## Task 4.5: Align Sample Log Assertions

**Files:**
- Modify: `packages/sample/test/app_smoke_test.dart`
- Modify: `packages/sample/test/logging_test.dart`

- [ ] **Step 1: Update sample log expectations**

Replace stale `eventCompleted` formatted-message expectations with `event.completed`.

- [ ] **Step 2: Run sample tests**

Run:

```bash
cd packages/sample && flutter test
```

Expected: PASS.

## Task 5: Workspace Verification

**Files:**
- Verify only; no planned file modifications.

- [ ] **Step 1: Format changed Dart files**

Run:

```bash
dart format --line-length 120 packages/arch_logger/lib packages/arch_logger/test
```

Expected: formatter completes successfully. If it changes files, review the diff before committing.

- [ ] **Step 2: Run arch logger tests**

Run:

```bash
cd packages/arch_logger && flutter test
```

Expected: PASS.

- [ ] **Step 3: Run logger tests to protect redaction behavior**

Run:

```bash
cd packages/logger && flutter test
```

Expected: PASS.

- [ ] **Step 4: Run arch tests to ensure core phases were not changed**

Run:

```bash
cd packages/arch && flutter test
```

Expected: PASS. Existing event logging tests should still prove the lifecycle phases and transition attribution.

- [ ] **Step 5: Run sample tests to protect visible log output**

Run:

```bash
cd packages/sample && flutter test
```

Expected: PASS.

- [ ] **Step 6: Run workspace analysis**

Run from the repository root:

```bash
flutter analyze
```

Expected: PASS with no new issues.

- [ ] **Step 7: Inspect final diff**

Run:

```bash
git diff --stat
git diff -- packages/arch_logger/lib packages/arch_logger/test docs/ARCHITECTURE.md docs/ARCHITECTURE-ko.md packages/arch_logger/README.md packages/logger/README.md packages/sample/test
```

Expected: diff only includes formatter interface, pretty formatter, tests, sample log assertions, and documentation for transition observability.

- [ ] **Step 8: Commit verification formatting changes if any**

If `dart format` changed files after Task 3 commits, run:

```bash
git add packages/arch_logger/lib packages/arch_logger/test
git commit -m "style: format blocpod transition formatter"
```

If there are no formatting changes, do not create a commit.

## Self-Review

Spec coverage:

- No `onChange` core phase is added.
- `transition` remains the canonical Blocpod state-assignment observation.
- Pretty output is implemented at the formatter layer.
- Compact structured output uses log-friendly phase labels.
- `hasChanged` remains the user-facing state-change field.
- Docs explain the BLoC comparison and Blocpod-specific direction.

Placeholder scan:

- This plan contains no deferred implementation placeholders.
- Each code-changing task includes concrete code or exact replacement text.
- Each test task includes the concrete test body and command.

Type consistency:

- `BlocpodEventLogFormatter` is defined in `event_log_record_formatter.dart`.
- `EventLogRecordFormatter` and `PrettyEventLogRecordFormatter` both implement `BlocpodEventLogFormatter`.
- `BlocpodEventLogger.formatter` uses `BlocpodEventLogFormatter`.
- `PrettyEventLogRecordFormatter.format` returns `BlocpodLogEntry`, matching the adapter contract.
- `eventLogPhaseLabel(EventLogPhase.transition)` returns `state.transition`.
