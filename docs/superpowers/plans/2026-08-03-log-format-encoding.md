# Blocpod Log Format Encoding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `blocpod_logger 0.2.0` with JSON Lines as the default debug-print format, an opt-in pretty format, structured sequence/trace/attributes fields, and a clean sink boundary for external logging adapters.

**Architecture:** Keep `BlocpodLogEntry` as the transport-neutral envelope and `BlocpodLogSink` as the external integration port. Add small encoder implementations for sinks that need strings, map architecture records into dedicated envelope fields plus nested event/state attributes, and keep the sample UI on the one-line pretty formatter while the default `DebugPrintLogSink` emits JSON.

**Tech Stack:** Dart 3.11.5+ / 3.12 workspace, Flutter, `dart:convert`, `flutter_test`, Riverpod 3.4.2, Dart pub workspaces

## Global Constraints

- `blocpod_logger` becomes `0.2.0`; `blocpod_arch` and `blocpod_arch_logger` remain `0.3.0`.
- `blocpod_arch_logger` and the private sample require `blocpod_logger: ^0.2.0`.
- `DebugPrintLogSink()` defaults to `const JsonLogEncoder()` and sends each encoded entry through one callback invocation.
- Every default JSON record has `schema: "blocpod.log"`, integer `schemaVersion: 1`, and a UTC ISO-8601 timestamp.
- JSON top-level framework keys and framework-generated attribute keys have deterministic insertion order; consumers must not assign semantic meaning to JSON object order.
- `BlocpodLogEntry.metadata` is removed without a deprecated alias and replaced by `attributes` plus `sequence`, `traceId`, `spanId`, and `parentSpanId`.
- `EventLogRecord.recordSequence` remains unchanged in `blocpod_arch` and maps to `BlocpodLogEntry.sequence` / JSON `sequence`.
- User event metadata is nested under `attributes.eventMetadata`; state metadata is nested under `attributes.stateMetadata`; neither is flattened into framework fields.
- Logger, formatter, and encoder code performs no automatic redaction. Documentation must state that callers own sensitive-data handling.
- Unsupported objects, throwing `toString()` implementations, cycles, and depth overflow must not escape from the built-in encoders.
- Cycle detection uses identity along the active recursion path. Reusing the same map or iterable in sibling branches is not a cycle.
- `maxDepth` applies to recursively normalized attribute/error values; the fixed JSON envelope itself does not consume that budget.
- `PrettyLogEncoder` uses no ANSI colors, hides sequence/trace/attributes in compact mode, and prints those diagnostics selectively in verbose mode.
- Built-in pretty error output may be multiline; ordinary pretty messages remain one line.
- External logger adapters implement `BlocpodLogSink` and receive `BlocpodLogEntry` directly. Do not add Talker or another logger SDK dependency, and do not export a concrete `UserProvidedLogSink`.
- Preserve the core synchronous FIFO observation order and `BlocpodEventLogger` failure isolation.
- Do not add file/network sinks, batching, retry, sampling, app/isolate IDs, or platform-specific adapters.
- Do not publish packages, push commits, or create tags as part of implementation.

---

## Spec Review Resolution

The approved design is implementable without an architecture change. The review found no release-blocking contradiction. Two normalization details are fixed above so separate implementers produce the same behavior: only an ancestor identity is a cycle, and pretty verbose rendering must use the same safe-value rules as JSON instead of calling arbitrary values unsafely.

## File Structure

- Modify `packages/logger/lib/src/blocpod_log_entry.dart`
  - Own the transport-neutral entry fields and the breaking `metadata` to `attributes` rename.
- Create `packages/logger/lib/src/blocpod_log_encoder.dart`
  - Own the public `BlocpodLogEncoder` interface.
- Create `packages/logger/lib/src/log_value_normalizer.dart`
  - Own private/package-internal JSON-safe normalization and safe scalar text used by both encoders.
- Create `packages/logger/lib/src/json_log_encoder.dart`
  - Own the versioned JSON envelope, deterministic key order, and minimal fallback.
- Create `packages/logger/lib/src/pretty_log_encoder.dart`
  - Own timestamp/level prefixes, compact/verbose diagnostics, and readable error rendering.
- Modify `packages/logger/lib/src/debug_print_log_sink.dart`
  - Inject an encoder, default it to JSON, and retain the compatibility formatting function.
- Modify `packages/logger/lib/blocpod_logger.dart`
  - Export the new public encoder APIs.
- Split `packages/logger/test/blocpod_logger_test.dart` into focused entry/sink coverage and create encoder-specific test files.
- Modify `packages/logger/test/dependency_direction_test.dart`
  - Cover both forbidden imports and forbidden external logger dependencies.
- Modify `packages/arch_logger/lib/src/event_log_record_formatter.dart`
  - Map sequence/trace into dedicated fields and framework/event/state values into ordered attributes.
- Modify `packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart`
  - Produce exactly one readable phase sentence and readable duration units.
- Modify `packages/arch_logger/test/blocpod_arch_logger_test.dart`
  - Lock field mapping, collision boundaries, all phase messages, durations, and failure records.
- Modify `packages/sample/lib/src/app.dart`
  - Install the pretty formatter and show message-only rows.
- Keep `packages/sample/lib/src/logging/in_memory_log_sink.dart`
  - Continue storing unencoded `BlocpodLogEntry` objects.
- Modify `packages/sample/test/logging_test.dart` and `packages/sample/test/app_smoke_test.dart`
  - Cover pretty UI output and real-dispatch JSON sequencing.
- Modify `packages/logger/pubspec.yaml`, `packages/arch_logger/pubspec.yaml`, and `packages/sample/pubspec.yaml`
  - Apply the approved package version constraints.
- Modify `packages/logger/README.md`, `packages/logger/CHANGELOG.md`, `packages/arch_logger/README.md`, `packages/arch_logger/CHANGELOG.md`, `packages/sample/README.md`, and root `README.md`
  - Document JSON default, pretty opt-in, migration, no-redaction contract, and adapter boundary.

---

### Task 1: Evolve the structured entry and public encoder contract

**Files:**
- Modify: `packages/logger/lib/src/blocpod_log_entry.dart`
- Create: `packages/logger/lib/src/blocpod_log_encoder.dart`
- Modify: `packages/logger/lib/src/debug_print_log_sink.dart`
- Modify: `packages/logger/lib/blocpod_logger.dart`
- Modify: `packages/logger/test/blocpod_logger_test.dart`

**Interfaces:**
- Produces: `BlocpodLogEntry({required BlocpodLogLevel level, required String message, required DateTime timestamp, int? sequence, String? traceId, String? spanId, String? parentSpanId, Map<String, Object?> attributes = const {}, Object? error, StackTrace? stackTrace})`.
- Produces: `abstract interface class BlocpodLogEncoder { String encode(BlocpodLogEntry entry); }`.
- Preserves: `abstract interface class BlocpodLogSink { void write(BlocpodLogEntry entry); }`.

- [ ] **Step 1: Replace the entry preservation test and add a direct user-sink test**

In `packages/logger/test/blocpod_logger_test.dart`, replace metadata-based construction with:

```dart
test('BlocpodLogEntry preserves transport-neutral structured fields', () {
  final error = StateError('failed');
  final stackTrace = StackTrace.current;
  final timestamp = DateTime.utc(2026, 8, 3);
  final entry = BlocpodLogEntry(
    level: BlocpodLogLevel.warning,
    message: 'dispatch finished',
    timestamp: timestamp,
    sequence: 41,
    traceId: 'trace-1',
    spanId: 'span-1',
    parentSpanId: 'span-0',
    attributes: const <String, Object?>{'phase': 'event.completed'},
    error: error,
    stackTrace: stackTrace,
  );

  expect(entry.level, BlocpodLogLevel.warning);
  expect(entry.message, 'dispatch finished');
  expect(entry.timestamp, timestamp);
  expect(entry.sequence, 41);
  expect(entry.traceId, 'trace-1');
  expect(entry.spanId, 'span-1');
  expect(entry.parentSpanId, 'span-0');
  expect(entry.attributes, containsPair('phase', 'event.completed'));
  expect(entry.error, same(error));
  expect(entry.stackTrace, same(stackTrace));
});

test('user-provided sink receives the original structured entry', () {
  final sink = RecordingSink();
  final entry = BlocpodLogEntry(
    level: BlocpodLogLevel.info,
    message: 'direct',
    timestamp: DateTime.utc(2026, 8, 3),
    sequence: 7,
    attributes: const <String, Object?>{'feature': 'counter'},
  );

  sink.write(entry);

  expect(sink.entries.single, same(entry));
  expect(sink.entries.single.sequence, 7);
});
```

Add this helper at file scope:

```dart
final class RecordingSink implements BlocpodLogSink {
  final List<BlocpodLogEntry> entries = <BlocpodLogEntry>[];

  @override
  void write(BlocpodLogEntry entry) => entries.add(entry);
}
```

- [ ] **Step 2: Run the focused test and verify the API change is red**

Run:

```bash
cd packages/logger && flutter test test/blocpod_logger_test.dart
```

Expected: compilation fails because `sequence`, trace fields, and `attributes` are not defined.

- [ ] **Step 3: Implement the entry fields and encoder interface**

Replace `BlocpodLogEntry` with the approved constructor and fields, including API documentation. In `debug_print_log_sink.dart`, change the temporary plain-text implementation from `_safeMetadata(entry.metadata)` to `_safeMetadata(entry.attributes)` so the package continues to compile until Task 4 replaces that implementation. Create `blocpod_log_encoder.dart` with:

```dart
import 'blocpod_log_entry.dart';

/// Converts a structured Blocpod log entry to text for string-based sinks.
abstract interface class BlocpodLogEncoder {
  /// Encodes [entry] without changing it.
  String encode(BlocpodLogEntry entry);
}
```

Export it from `packages/logger/lib/blocpod_logger.dart`:

```dart
export 'src/blocpod_log_encoder.dart';
```

- [ ] **Step 4: Run the focused test and verify it passes**

Run:

```bash
cd packages/logger && flutter test test/blocpod_logger_test.dart
```

Expected: PASS after changing existing test constructors and assertions from `metadata` to `attributes`; the temporary plain-text redaction assertions remain green until Task 4 deliberately replaces them with the approved no-redaction JSON contract.

- [ ] **Step 5: Commit the entry contract**

```bash
git add packages/logger/lib/src/blocpod_log_entry.dart packages/logger/lib/src/blocpod_log_encoder.dart packages/logger/lib/src/debug_print_log_sink.dart packages/logger/lib/blocpod_logger.dart packages/logger/test/blocpod_logger_test.dart
git commit -m "feat(logger): add structured log entry fields"
```

---

### Task 2: Implement safe JSON Lines encoding

**Files:**
- Create: `packages/logger/lib/src/log_value_normalizer.dart`
- Create: `packages/logger/lib/src/json_log_encoder.dart`
- Modify: `packages/logger/lib/blocpod_logger.dart`
- Create: `packages/logger/test/json_log_encoder_test.dart`

**Interfaces:**
- Consumes: `BlocpodLogEncoder` and the Task 1 `BlocpodLogEntry` fields.
- Produces: `const JsonLogEncoder({int maxDepth = 8})` implementing `BlocpodLogEncoder`.
- Produces internally: `Object? normalizeLogValue(Object? value, {required int maxDepth})` with identity-based active-path cycle detection.
- Produces internally: `String safeLogText(Object value)` for non-throwing fallback text.

- [ ] **Step 1: Write failing envelope and omission tests**

Create `packages/logger/test/json_log_encoder_test.dart` with imports for `dart:convert`, `blocpod_logger`, and `flutter_test`, then add:

```dart
group('JsonLogEncoder', () {
  const encoder = JsonLogEncoder();

  test('emits a deterministic one-line versioned envelope', () {
    final encoded = encoder.encode(
      BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: 'Counter transition\nquoted "value"',
        timestamp: DateTime.parse('2026-08-03T10:00:01.001+09:00'),
        sequence: 104,
        traceId: 'trace-ab12',
        spanId: 'span-cd34',
        parentSpanId: 'span-parent',
        attributes: const <String, Object?>{'phase': 'state.transition', 'hasChanged': true},
      ),
    );

    expect(encoded.contains('\n'), isFalse);
    expect(
      encoded,
      '{"schema":"blocpod.log","schemaVersion":1,"timestamp":"2026-08-03T01:00:01.001Z",'
      '"sequence":104,"level":"info","message":"Counter transition\\nquoted \\"value\\"",'
      '"trace":{"traceId":"trace-ab12","spanId":"span-cd34","parentSpanId":"span-parent"},'
      '"attributes":{"phase":"state.transition","hasChanged":true}}',
    );
    expect(jsonDecode(encoded), isA<Map<String, Object?>>());
  });

  test('omits absent optional sections and null trace members', () {
    final withoutOptional = encoder.encode(
      BlocpodLogEntry(
        level: BlocpodLogLevel.debug,
        message: 'created',
        timestamp: DateTime.utc(2026, 8, 3),
      ),
    );
    final partialTrace = jsonDecode(
      encoder.encode(
        BlocpodLogEntry(
          level: BlocpodLogLevel.info,
          message: 'partial trace',
          timestamp: DateTime.utc(2026, 8, 3),
          spanId: 'span-only',
        ),
      ),
    ) as Map<String, Object?>;

    expect(jsonDecode(withoutOptional), <String, Object?>{
      'schema': 'blocpod.log',
      'schemaVersion': 1,
      'timestamp': '2026-08-03T00:00:00.000Z',
      'level': 'debug',
      'message': 'created',
    });
    expect(partialTrace['trace'], <String, Object?>{'spanId': 'span-only'});
  });

  test('round-trips quotes, backslashes, and line breaks through JSON escaping', () {
    const message = 'quoted "value" at C:\\temp\nnext line';
    final encoded = encoder.encode(
      BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: message,
        timestamp: DateTime.utc(2026, 8, 3),
      ),
    );

    expect(encoded.contains('\n'), isFalse);
    expect((jsonDecode(encoded) as Map<String, Object?>)['message'], message);
  });

  test('rejects non-positive maxDepth in checked builds', () {
    expect(() => JsonLogEncoder(maxDepth: 0), throwsAssertionError);
  });
});
```

- [ ] **Step 2: Run the JSON test and verify it fails**

Run:

```bash
cd packages/logger && flutter test test/json_log_encoder_test.dart
```

Expected: compilation fails because `JsonLogEncoder` is not defined.

- [ ] **Step 3: Implement the ordered envelope and structured error**

Create `json_log_encoder.dart`. Build a `LinkedHashMap`-ordered map using a literal in this exact order: `schema`, `schemaVersion`, `timestamp`, optional `sequence`, `level`, `message`, optional `trace`, optional `attributes`, optional `error`. Use `jsonEncode` once. Error construction must be:

```dart
if (entry.error != null || entry.stackTrace != null)
  'error': <String, Object?>{
    if (entry.error != null) 'type': entry.error.runtimeType.toString(),
    if (entry.error != null) 'message': safeLogText(entry.error!),
    if (entry.stackTrace != null) 'stackTrace': safeLogText(entry.stackTrace!),
  },
```

Wrap the whole encode operation in `try/catch` and return this valid JSON shape on failure, using the entry timestamp when conversion succeeds and UTC `DateTime.now()` only if timestamp formatting itself unexpectedly fails:

```dart
<String, Object?>{
  'schema': 'blocpod.log',
  'schemaVersion': 1,
  'timestamp': fallbackTimestamp,
  'level': 'error',
  'message': 'Blocpod log encoding failed',
}
```

- [ ] **Step 4: Add normalization tests before implementing normalization**

Add test fixtures and tests to `json_log_encoder_test.dart`:

```dart
enum ExamplePhase { started }

final class ThrowingText {
  @override
  String toString() => throw StateError('cannot stringify');
}

test('normalizes Dart values without redaction', () {
  final decoded = jsonDecode(
    const JsonLogEncoder().encode(
      BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: 'values',
        timestamp: DateTime.utc(2026, 8, 3),
        attributes: <String, Object?>{
          'when': DateTime.parse('2026-08-03T09:00:00+09:00'),
          'elapsed': const Duration(microseconds: 1250),
          'phaseEnum': ExamplePhase.started,
          'numbers': <Object?>[1, 1.5, double.nan, double.infinity, double.negativeInfinity],
          'password': 'kept-by-contract',
          'odd': ThrowingText(),
          'oddKeys': <Object?, Object?>{1: 'numeric-key', '1': 'string-key-wins'},
        },
      ),
    ),
  ) as Map<String, Object?>;
  final attributes = decoded['attributes'] as Map<String, Object?>;

  expect(attributes['when'], '2026-08-03T00:00:00.000Z');
  expect(attributes['elapsed'], 1250);
  expect(attributes['phaseEnum'], 'started');
  expect(attributes['numbers'], <Object?>[1, 1.5, 'NaN', 'Infinity', '-Infinity']);
  expect(attributes['password'], 'kept-by-contract');
  expect(attributes['odd'], '<ThrowingText>');
  expect(attributes['oddKeys'], <String, Object?>{'1': 'string-key-wins'});
});

test('marks active-path cycles but preserves shared sibling values', () {
  final cycle = <Object?>[];
  cycle.add(cycle);
  final mapCycle = <String, Object?>{};
  mapCycle['self'] = mapCycle;
  final shared = <String, Object?>{'value': 1};
  final decoded = jsonDecode(
    const JsonLogEncoder().encode(
      BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: 'graph',
        timestamp: DateTime.utc(2026, 8, 3),
        attributes: <String, Object?>{
          'iterableCycle': cycle,
          'mapCycle': mapCycle,
          'left': shared,
          'right': shared,
        },
      ),
    ),
  ) as Map<String, Object?>;
  final attributes = decoded['attributes'] as Map<String, Object?>;

  expect(attributes['iterableCycle'], <Object?>['<cycle>']);
  expect(attributes['mapCycle'], <String, Object?>{'self': '<cycle>'});
  expect(attributes['left'], <String, Object?>{'value': 1});
  expect(attributes['right'], <String, Object?>{'value': 1});
});

test('marks values beyond maxDepth', () {
  final decoded = jsonDecode(
    const JsonLogEncoder(maxDepth: 2).encode(
      BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: 'depth',
        timestamp: DateTime.utc(2026, 8, 3),
        attributes: const <String, Object?>{
          'root': <String, Object?>{'child': <String, Object?>{'leaf': 1}},
        },
      ),
    ),
  ) as Map<String, Object?>;

  expect(
    (decoded['attributes'] as Map<String, Object?>)['root'],
    <String, Object?>{'child': '<max-depth-exceeded>'},
  );
});
```

- [ ] **Step 5: Implement the shared safe normalizer**

In `log_value_normalizer.dart`, normalize primitive values first, convert finite and non-finite numbers separately, then `DateTime`, `Duration`, `Enum`, `Map`, `Iterable`, and fallback objects. For maps and iterables, add the object identity to an `HashSet<Object>.identity()` before recursion and remove it in `finally`. Convert map keys through `safeLogText`; later collisions overwrite earlier entries. Use `depth >= maxDepth` only when another map/iterable expansion would occur, so scalar leaves at the configured boundary remain intact.

Expose the helper only through `src/` imports; do not export it from `blocpod_logger.dart`. Keep `JsonLogEncoder`'s public constructor exactly `const JsonLogEncoder({this.maxDepth = 8}) : assert(maxDepth > 0);`.

- [ ] **Step 6: Add and pass error/fallback tests**

Add these error tests:

```dart
test('encodes errors and stack traces as a structured object', () {
  final decoded = jsonDecode(
    const JsonLogEncoder().encode(
      BlocpodLogEntry(
        level: BlocpodLogLevel.error,
        message: 'failed',
        timestamp: DateTime.utc(2026, 8, 3),
        error: StateError('boom'),
        stackTrace: StackTrace.fromString('#0 save\n#1 dispatch'),
      ),
    ),
  ) as Map<String, Object?>;

  expect(decoded['error'], <String, Object?>{
    'type': 'StateError',
    'message': 'Bad state: boom',
    'stackTrace': '#0 save\n#1 dispatch',
  });
});

test('stack-trace-only errors omit type and message', () {
  final decoded = jsonDecode(
    const JsonLogEncoder().encode(
      BlocpodLogEntry(
        level: BlocpodLogLevel.error,
        message: 'failed',
        timestamp: DateTime.utc(2026, 8, 3),
        stackTrace: StackTrace.fromString('#0 dispatch'),
      ),
    ),
  ) as Map<String, Object?>;

  expect(decoded['error'], <String, Object?>{'stackTrace': '#0 dispatch'});
});
```

Add this deterministic failure fixture:

```dart
final class ThrowingStringMap extends MapBase<String, Object?> {
  @override
  Object? operator [](Object? key) => null;

  @override
  void operator []=(String key, Object? value) {}

  @override
  void clear() {}

  @override
  Iterable<String> get keys => throw StateError('cannot iterate');

  @override
  Object? remove(Object? key) => null;
}
```

Import `dart:collection`, pass `ThrowingStringMap()` as `attributes`, and assert `jsonDecode(result)` equals the five-field fallback envelope and `result.contains('\n')` is false.

```dart
test('returns minimal valid JSON when normalization fails completely', () {
  final result = const JsonLogEncoder().encode(
    BlocpodLogEntry(
      level: BlocpodLogLevel.info,
      message: 'unencodable',
      timestamp: DateTime.utc(2026, 8, 3),
      attributes: ThrowingStringMap(),
    ),
  );

  expect(result.contains('\n'), isFalse);
  expect(jsonDecode(result), <String, Object?>{
    'schema': 'blocpod.log',
    'schemaVersion': 1,
    'timestamp': '2026-08-03T00:00:00.000Z',
    'level': 'error',
    'message': 'Blocpod log encoding failed',
  });
});
```

Run:

```bash
cd packages/logger && flutter test test/json_log_encoder_test.dart
```

Expected: PASS for envelope, omission, error, escaping, normalization, cycle, depth, no-redaction, and fallback cases.

- [ ] **Step 7: Export and commit the JSON encoder**

Add:

```dart
export 'src/json_log_encoder.dart';
```

Then commit:

```bash
git add packages/logger/lib/src/log_value_normalizer.dart packages/logger/lib/src/json_log_encoder.dart packages/logger/lib/blocpod_logger.dart packages/logger/test/json_log_encoder_test.dart
git commit -m "feat(logger): add safe JSON Lines encoder"
```

---

### Task 3: Implement compact and verbose pretty encoding

**Files:**
- Create: `packages/logger/lib/src/pretty_log_encoder.dart`
- Modify: `packages/logger/lib/blocpod_logger.dart`
- Create: `packages/logger/test/pretty_log_encoder_test.dart`

**Interfaces:**
- Consumes: Task 1 entry fields and Task 2 safe-value helpers.
- Produces: `enum PrettyLogDetail { compact, verbose }`.
- Produces: `const PrettyLogEncoder({PrettyLogDetail detail = PrettyLogDetail.compact})`.

- [ ] **Step 1: Write failing compact, verbose, and error tests**

Create `packages/logger/test/pretty_log_encoder_test.dart` with:

```dart
group('PrettyLogEncoder', () {
  final entry = BlocpodLogEntry(
    level: BlocpodLogLevel.info,
    message: '✨ CounterController · IncrementEvent transition[1] data(count:0) → data(count:1)',
    timestamp: DateTime.parse('2026-08-03T19:00:01.001+09:00'),
    sequence: 104,
    traceId: 'trace-ab12',
    spanId: 'span-cd34',
    parentSpanId: 'span-parent',
    attributes: const <String, Object?>{'phase': 'state.transition', 'transitionIndex': 1},
  );

  test('compact prints only time, level, and message', () {
    expect(
      const PrettyLogEncoder().encode(entry),
      '10:00:01.001Z INFO  ✨ CounterController · IncrementEvent transition[1] data(count:0) → data(count:1)',
    );
  });

  test('verbose appends only available diagnostics', () {
    expect(
      const PrettyLogEncoder(detail: PrettyLogDetail.verbose).encode(entry),
      '10:00:01.001Z INFO  ✨ CounterController · IncrementEvent transition[1] data(count:0) → data(count:1)\n'
      '  sequence=104 trace=trace-ab12/span-cd34 parent=span-parent\n'
      '  attributes={phase: state.transition, transitionIndex: 1}',
    );
  });

  test('compact renders error and stack trace on following lines', () {
    final output = const PrettyLogEncoder().encode(
      BlocpodLogEntry(
        level: BlocpodLogLevel.error,
        message: '🔴 Save failed',
        timestamp: DateTime.utc(2026, 8, 3, 10),
        error: StateError('save failed'),
        stackTrace: StackTrace.fromString('#0 save\n#1 dispatch'),
      ),
    );

    expect(
      output,
      '10:00:00.000Z ERROR 🔴 Save failed\n'
      '  StateError: Bad state: save failed\n'
      '  #0 save\n'
      '  #1 dispatch',
    );
  });
});
```

- [ ] **Step 2: Run the pretty tests and verify they fail**

Run:

```bash
cd packages/logger && flutter test test/pretty_log_encoder_test.dart
```

Expected: compilation fails because `PrettyLogEncoder` and `PrettyLogDetail` are not defined.

- [ ] **Step 3: Implement deterministic pretty output**

Create `pretty_log_encoder.dart`. Format UTC time from `timestamp.toUtc().toIso8601String().substring(11)`; uppercase levels and right-pad `INFO` to five characters so the message column aligns. Append diagnostics only when present. Render attributes recursively with `{key: value}` / `[value]` notation using the Task 2 normalizer so cycles, depth overflow, non-finite values, and throwing `toString()` remain safe. Prefix every error and stack-trace line with two spaces.

The trace diagnostic rules are:

```dart
final trace = switch ((entry.traceId, entry.spanId)) {
  (final traceId?, final spanId?) => '$traceId/$spanId',
  (final traceId?, null) => traceId,
  (null, final spanId?) => spanId,
  (null, null) => null,
};
```

Do not emit an empty sequence/trace line or an empty attributes line.

- [ ] **Step 4: Add safety and omission regression tests**

Add these regression tests (define the same small `ThrowingText` fixture in this test library):

```dart
test('verbose safely renders cycles and throwing objects', () {
  final cycle = <Object?>[];
  cycle.add(cycle);
  final output = const PrettyLogEncoder(detail: PrettyLogDetail.verbose).encode(
    BlocpodLogEntry(
      level: BlocpodLogLevel.info,
      message: 'safe values',
      timestamp: DateTime.utc(2026, 8, 3),
      attributes: <String, Object?>{'cycle': cycle, 'odd': ThrowingText()},
    ),
  );

  expect(output, contains('<cycle>'));
  expect(output, contains('<ThrowingText>'));
});

test('compact hides diagnostics and empty verbose adds no lines', () {
  final compact = const PrettyLogEncoder().encode(entry);
  expect(compact, isNot(contains('sequence=')));
  expect(compact, isNot(contains('trace=')));
  expect(compact, isNot(contains('attributes=')));

  final plain = BlocpodLogEntry(
    level: BlocpodLogLevel.info,
    message: 'plain',
    timestamp: DateTime.utc(2026, 8, 3),
  );
  expect(
    const PrettyLogEncoder(detail: PrettyLogDetail.verbose).encode(plain),
    const PrettyLogEncoder().encode(plain),
  );
});
```

- [ ] **Step 5: Run tests, export, and commit**

Run:

```bash
cd packages/logger && flutter test test/pretty_log_encoder_test.dart
```

Expected: PASS.

Export both public types and commit:

```bash
git add packages/logger/lib/src/pretty_log_encoder.dart packages/logger/lib/blocpod_logger.dart packages/logger/test/pretty_log_encoder_test.dart
git commit -m "feat(logger): add pretty log encoder"
```

---

### Task 4: Make JSON the debug-print default

**Files:**
- Modify: `packages/logger/lib/src/debug_print_log_sink.dart`
- Modify: `packages/logger/test/blocpod_logger_test.dart`

**Interfaces:**
- Consumes: `BlocpodLogEncoder`, `JsonLogEncoder`, and `PrettyLogEncoder`.
- Produces: `DebugPrintLogSink({BlocpodLogEncoder encoder = const JsonLogEncoder(), DebugPrintCallback? debugPrintOverride})`.
- Preserves: `String formatBlocpodLogEntry(BlocpodLogEntry entry)` while changing its output to JSON.

- [ ] **Step 1: Write failing sink default and injection tests**

Add these tests to `blocpod_logger_test.dart`:

```dart
test('DebugPrintLogSink uses JSON Lines by default in one callback', () {
  final messages = <String>[];
  final sink = DebugPrintLogSink(
    debugPrintOverride: (message, {wrapWidth}) => messages.add(message ?? ''),
  );
  sink.write(
    BlocpodLogEntry(
      level: BlocpodLogLevel.info,
      message: 'created',
      timestamp: DateTime.utc(2026, 8, 3),
    ),
  );

  expect(messages, hasLength(1));
  expect(jsonDecode(messages.single), containsPair('schema', 'blocpod.log'));
});

test('DebugPrintLogSink uses the injected encoder', () {
  final messages = <String>[];
  final sink = DebugPrintLogSink(
    encoder: const PrefixEncoder(),
    debugPrintOverride: (message, {wrapWidth}) => messages.add(message ?? ''),
  );
  sink.write(
    BlocpodLogEntry(
      level: BlocpodLogLevel.info,
      message: 'created',
      timestamp: DateTime.utc(2026, 8, 3),
    ),
  );

  expect(messages, <String>['encoded:created']);
});

test('formatBlocpodLogEntry delegates to the default JSON encoder', () {
  final entry = BlocpodLogEntry(
    level: BlocpodLogLevel.info,
    message: 'created',
    timestamp: DateTime.utc(2026, 8, 3),
  );
  expect(formatBlocpodLogEntry(entry), const JsonLogEncoder().encode(entry));
});

final class PrefixEncoder implements BlocpodLogEncoder {
  const PrefixEncoder();

  @override
  String encode(BlocpodLogEntry entry) => 'encoded:${entry.message}';
}
```

Add `dart:convert` to the test imports.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
cd packages/logger && flutter test test/blocpod_logger_test.dart
```

Expected: default output is still plain text and the constructor rejects `encoder`.

- [ ] **Step 3: Replace formatting/redaction logic with encoder delegation**

Give `DebugPrintLogSink` a final `BlocpodLogEncoder _encoder`, initialize it from the constructor, and implement:

```dart
@override
void write(BlocpodLogEntry entry) {
  _debugPrint(_encoder.encode(entry));
}

String formatBlocpodLogEntry(BlocpodLogEntry entry) {
  return const JsonLogEncoder().encode(entry);
}
```

Delete `_safeMetadata`, `_safeValue`, and `_isSensitiveKey` entirely.

- [ ] **Step 4: Run all logger tests and commit**

Run:

```bash
cd packages/logger && flutter test
```

Expected: PASS, including assertions that keys named `token`, `secret`, `credential`, and `password` are retained by the JSON encoder.

```bash
git add packages/logger/lib/src/debug_print_log_sink.dart packages/logger/test/blocpod_logger_test.dart
git commit -m "feat(logger): default debug output to JSON Lines"
```

---

### Task 5: Map architecture records into the new envelope

**Files:**
- Modify: `packages/arch_logger/lib/src/event_log_record_formatter.dart`
- Modify: `packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart`
- Modify: `packages/arch_logger/test/blocpod_arch_logger_test.dart`

**Interfaces:**
- Consumes: Task 1 `BlocpodLogEntry` fields and existing `EventLogRecord` fields.
- Produces: dedicated `sequence`, `traceId`, `spanId`, `parentSpanId` values.
- Produces: ordered framework attributes followed by optional `eventMetadata` and `stateMetadata` objects.

- [ ] **Step 1: Rewrite mapping tests for dedicated fields and nested metadata**

Change the primary mapping assertion to:

```dart
expect(entry.sequence, record.recordSequence);
expect(entry.traceId, record.traceContext.traceId);
expect(entry.spanId, record.traceContext.spanId);
expect(entry.parentSpanId, record.traceContext.parentSpanId);
expect(entry.attributes, <String, Object?>{
  'phase': 'event.completed',
  'controllerName': 'CounterController',
  'eventName': 'IncrementEvent',
  'durationMicros': 12000,
  'previousStateKind': 'loading',
  'nextStateKind': 'data',
  'hasChanged': true,
  'eventMetadata': <String, Object?>{'feature': 'counter'},
});
```

Add a record with `recordSequence: 42`, caller metadata containing `phase`, `sequence`, and `traceId`, plus state metadata. Assert the dedicated fields retain record values, while all caller keys survive only inside `eventMetadata` and cannot replace framework `attributes['phase']`. Assert `stateMetadata` is a separate sibling object.

- [ ] **Step 2: Run arch logger tests and verify compilation/assertion failures**

Run:

```bash
cd packages/arch_logger && flutter test test/blocpod_arch_logger_test.dart
```

Expected: compilation fails at `.metadata`, or assertions fail because sequence/trace are still flattened.

- [ ] **Step 3: Implement dedicated mapping and deterministic attributes**

Remove both reserved-key sets. Construct the entry as:

```dart
return BlocpodLogEntry(
  level: record.error == null ? BlocpodLogLevel.info : BlocpodLogLevel.error,
  message: _messageFor(record),
  timestamp: record.occurredAt,
  sequence: record.recordSequence,
  traceId: record.traceContext.traceId,
  spanId: record.traceContext.spanId,
  parentSpanId: record.traceContext.parentSpanId,
  attributes: <String, Object?>{
    'phase': eventLogPhaseLabel(record.phase),
    'controllerName': record.controllerName,
    if (record.eventName != null) 'eventName': record.eventName,
    if (record.duration != null) 'durationMicros': record.duration!.inMicroseconds,
    if (record.transitionIndex != null) 'transitionIndex': record.transitionIndex,
    if (record.previousStateKind != null) 'previousStateKind': record.previousStateKind!.name,
    if (record.nextStateKind != null) 'nextStateKind': record.nextStateKind!.name,
    if (record.hasChanged != null) 'hasChanged': record.hasChanged,
    if (record.previousStateLabel != null) 'previousStateLabel': record.previousStateLabel,
    if (record.nextStateLabel != null) 'nextStateLabel': record.nextStateLabel,
    if (record.metadata.isNotEmpty) 'eventMetadata': record.metadata,
    if (record.stateMetadata.isNotEmpty) 'stateMetadata': record.stateMetadata,
  },
  error: record.error,
  stackTrace: record.stackTrace,
);
```

Update `PrettyEventLogRecordFormatter.format` to copy every dedicated field and `attributes` from the compact entry while replacing only `message`.

- [ ] **Step 4: Add raw-sink and key-order assertions**

Use a fully populated transition and assert the raw entry shape directly:

```dart
final entry = const EventLogRecordFormatter().format(record);

expect(entry.sequence, 42);
expect(entry.traceId, record.traceContext.traceId);
expect(entry.attributes.keys, orderedEquals(<String>[
  'phase',
  'controllerName',
  'eventName',
  'durationMicros',
  'transitionIndex',
  'previousStateKind',
  'nextStateKind',
  'hasChanged',
  'previousStateLabel',
  'nextStateLabel',
  'eventMetadata',
  'stateMetadata',
]));

final sink = MemoryLogSink()..write(entry);
expect(sink.entries.single, same(entry));
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
cd packages/arch_logger && flutter test test/blocpod_arch_logger_test.dart
```

Expected: PASS for field mapping, collision isolation, null omission, initial state, transitions, and failures.

```bash
git add packages/arch_logger/lib/src/event_log_record_formatter.dart packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart packages/arch_logger/test/blocpod_arch_logger_test.dart
git commit -m "feat(arch_logger): map records to structured log envelope"
```

---

### Task 6: Make all pretty event messages concise and one-line

**Files:**
- Modify: `packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart`
- Modify: `packages/arch_logger/test/blocpod_arch_logger_test.dart`

**Interfaces:**
- Consumes: all seven `EventLogPhase` variants.
- Produces: one-line message strings with phase emoji, controller/event names, state summaries, transition index, and formatted duration.
- Produces internally: `_formatDuration(Duration duration)` with `µs`, `ms`, or up-to-two-decimal `s` output.

- [ ] **Step 1: Replace multiline assertions with an exact phase table**

Add a table-driven test whose expected messages are:

```dart
<EventLogPhase, String>{
  EventLogPhase.controllerCreated: '🟢 CounterController created',
  EventLogPhase.initialStateEstablished: '🔵 CounterController established data(ready)',
  EventLogPhase.eventStarted: '🟡 CounterController · IncrementEvent started from loading(count:0)',
  EventLogPhase.transition:
      '✨ CounterController · IncrementEvent transition[1] loading(count:0) → data(count:1)',
  EventLogPhase.eventCompleted:
      '✅ CounterController · IncrementEvent completed loading(count:0) → data(count:1) in 12ms',
  EventLogPhase.eventFailed:
      '🔴 CounterController · IncrementEvent failed loading(count:0) → data(count:1) in 12ms',
  EventLogPhase.controllerDisposed: '⚪ CounterController disposed',
};
```

Add this helper in the test file and use it for the table:

```dart
EventLogRecord prettyRecordFor(EventLogPhase phase) {
  final startedAt = DateTime.utc(2026, 8, 3, 10);
  final isEvent = switch (phase) {
    EventLogPhase.eventStarted ||
    EventLogPhase.transition ||
    EventLogPhase.eventCompleted ||
    EventLogPhase.eventFailed => true,
    _ => false,
  };
  return EventLogRecord(
    phase: phase,
    traceContext: TraceContext.root(startedAt: startedAt),
    controllerName: 'CounterController',
    eventName: isEvent ? 'IncrementEvent' : null,
    startedAt: startedAt,
    duration: phase == EventLogPhase.eventCompleted || phase == EventLogPhase.eventFailed
        ? const Duration(milliseconds: 12)
        : null,
    transitionIndex: phase == EventLogPhase.transition ? 1 : null,
    previousStateKind: isEvent ? AsyncValueKind.loading : null,
    previousStateLabel: isEvent ? 'count:0' : null,
    nextStateKind: switch (phase) {
      EventLogPhase.initialStateEstablished ||
      EventLogPhase.transition ||
      EventLogPhase.eventCompleted ||
      EventLogPhase.eventFailed => AsyncValueKind.data,
      _ => null,
    },
    nextStateLabel: switch (phase) {
      EventLogPhase.initialStateEstablished => 'ready',
      EventLogPhase.transition || EventLogPhase.eventCompleted || EventLogPhase.eventFailed => 'count:1',
      _ => null,
    },
    error: phase == EventLogPhase.eventFailed ? StateError('failed') : null,
  );
}
```

Assert every result has neither `\n` nor `\r`.

- [ ] **Step 2: Add duration boundary tests**

Use completed records and assert exact suffixes for:

```dart
const <Duration, String>{
  Duration(microseconds: 840): '840µs',
  Duration(microseconds: 1000): '1ms',
  Duration(milliseconds: 124): '124ms',
  Duration(milliseconds: 999): '999ms',
  Duration(seconds: 1): '1s',
  Duration(milliseconds: 1240): '1.24s',
  Duration(milliseconds: 2000): '2s',
};
```

- [ ] **Step 3: Run focused tests and verify old multiline output fails**

Run:

```bash
cd packages/arch_logger && flutter test test/blocpod_arch_logger_test.dart
```

Expected: exact-message and duration assertions fail against the old multiline formatter.

- [ ] **Step 4: Implement phase sentence helpers**

Replace metadata-key summaries and redaction helpers with `_stateText`, `_stateChangeText`, and `_formatDuration`. `_formatDuration` must use integer microseconds below 1 ms, integer truncated milliseconds below 1 second, and `(microseconds / Duration.microsecondsPerSecond).toStringAsFixed(2)` with trailing zeros and the trailing decimal point removed at or above 1 second.

Use `unknownEvent` only when an event phase unexpectedly lacks a name; use `unknown` for a missing state kind. Do not append attributes, trace, or sequence to the message because the encoder controls that detail.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
cd packages/arch_logger && flutter test
```

Expected: PASS for all phase, duration, structured-field, error-level, and failure-isolation tests.

```bash
git add packages/arch_logger/lib/src/pretty_event_log_record_formatter.dart packages/arch_logger/test/blocpod_arch_logger_test.dart
git commit -m "feat(arch_logger): simplify pretty event messages"
```

---

### Task 7: Update sample behavior and add real-dispatch JSON coverage

**Files:**
- Modify: `packages/sample/lib/src/app.dart`
- Modify: `packages/sample/test/logging_test.dart`
- Modify: `packages/sample/test/app_smoke_test.dart`

**Interfaces:**
- Consumes: `PrettyEventLogRecordFormatter`, `JsonLogEncoder`, and the existing `InMemoryLogSink`.
- Preserves: in-memory storage of unencoded entries.
- Produces: message-only sample rows using one-line pretty messages.

- [ ] **Step 1: Write failing sample formatter and JSON sequence tests**

Change the logging test override to:

```dart
eventLoggerProvider.overrideWithValue(
  BlocpodEventLogger(sink, formatter: const PrettyEventLogRecordFormatter()),
)
```

After a counter dispatch, assert the stable sentence fields and a duration-unit suffix without hard-coding elapsed wall-clock time:

```dart
expect(
  sink.entries.map((entry) => entry.message),
  contains(
    matches(
      RegExp(
        r'^✅ SampleCounterController · CounterIncremented completed data\(count:0\) → '
        r'data\(count:1\) in (\d+µs|\d+ms|\d+(?:\.\d{1,2})?s)$',
      ),
    ),
  ),
);
expect(sink.entries.last.attributes, containsPair('controllerName', 'SampleCounterController'));
expect(sink.entries.last.sequence, isNotNull);
```

Add a second test that maps every captured entry through `const JsonLogEncoder().encode`, decodes each line, and asserts:

```dart
expect(lines, everyElement(isNot(contains('\n'))));
expect(decoded, everyElement(containsPair('schema', 'blocpod.log')));
final sequences = decoded.map((json) => json['sequence']! as int).toList();
expect(sequences, orderedEquals(<int>[...sequences]..sort()));
expect(
  decoded.map((json) => (json['attributes']! as Map<String, Object?>)['phase']),
  containsAllInOrder(<String>['event.started', 'state.transition', 'event.completed']),
);
```

Add a third test proving a string-sink encoder failure remains isolated from a real dispatch:

```dart
test('encoder failure does not change the dispatch result', () async {
  final sink = DebugPrintLogSink(
    encoder: const ThrowingEncoder(),
    debugPrintOverride: (message, {wrapWidth}) {},
  );
  final container = ProviderContainer(
    overrides: [
      eventLoggerProvider.overrideWithValue(BlocpodEventLogger(sink)),
    ],
  );
  addTearDown(container.dispose);

  await expectLater(
    container.read(counterProvider.notifier).dispatch(const CounterIncremented(1)),
    completes,
  );
  expect(container.read(counterProvider).value, 1);
});

final class ThrowingEncoder implements BlocpodLogEncoder {
  const ThrowingEncoder();

  @override
  String encode(BlocpodLogEntry entry) => throw StateError('encoder failed');
}
```

- [ ] **Step 2: Run sample tests and verify old formatter/API failures**

Run:

```bash
cd packages/sample && flutter test test/logging_test.dart test/app_smoke_test.dart
```

Expected: assertions fail because the app still installs the compact formatter and the UI still reads `.metadata`.

- [ ] **Step 3: Install the pretty formatter and simplify the event list**

In `BlocpodSampleApp`, use:

```dart
eventLoggerProvider.overrideWithValue(
  BlocpodEventLogger(_sink, formatter: const PrettyEventLogRecordFormatter()),
),
```

In `EventLogPanel`, keep `Text(entry.message)` and remove `_reservedLogMetadataKeys`, `_visibleMetadata`, and the secondary metadata `Text`. Keep `InMemoryLogSink` unchanged.

- [ ] **Step 4: Align widget assertions and pass sample tests**

Change widget assertions from `event.completed` and flattened metadata text to:

```dart
expect(_textContaining('✅ SampleCounterController · CounterIncremented completed'), findsAtLeastNWidgets(1));
expect(_textContaining('VariantCounterController'), findsAtLeastNWidgets(1));
expect(_textContaining('providerName='), findsNothing);
expect(_textContaining('providerKind='), findsNothing);
expect(_textContaining('sequence='), findsNothing);
```

Run:

```bash
cd packages/sample && flutter test
```

Expected: PASS, with sample rows showing pretty messages only and integration JSON preserving sequence order and phase order.

- [ ] **Step 5: Commit sample behavior**

```bash
git add packages/sample/lib/src/app.dart packages/sample/test/logging_test.dart packages/sample/test/app_smoke_test.dart
git commit -m "feat(sample): show concise pretty event logs"
```

---

### Task 8: Apply release metadata, migration docs, and dependency guards

**Files:**
- Modify: `packages/logger/pubspec.yaml`
- Modify: `packages/arch_logger/pubspec.yaml`
- Modify: `packages/sample/pubspec.yaml`
- Modify: `packages/logger/test/dependency_direction_test.dart`
- Modify: `packages/logger/README.md`
- Modify: `packages/logger/CHANGELOG.md`
- Modify: `packages/arch_logger/README.md`
- Modify: `packages/arch_logger/CHANGELOG.md`
- Modify: `packages/sample/README.md`
- Modify: `README.md`
- Modify: `pubspec.lock` only when `flutter pub get` changes it

**Interfaces:**
- Produces: published package metadata for `blocpod_logger 0.2.0`.
- Preserves: `blocpod_arch_logger 0.3.0` while requiring `blocpod_logger ^0.2.0`.
- Documents: JSON default, pretty opt-in, breaking migration, no-redaction contract, and sink adapter boundary.

- [ ] **Step 1: Strengthen the dependency-direction test**

Extend `dependency_direction_test.dart` with a test that reads `pubspec.yaml` and all `lib/**/*.dart` files and asserts they contain none of these package/import fragments:

```dart
const forbiddenExternalLoggers = <String>[
  'package:talker/',
  'package:logging/',
  'package:sentry/',
  'package:firebase_crashlytics/',
];
```

Use this body:

```dart
test('blocpod_logger has no external logger SDK dependency', () {
  const forbiddenExternalLoggers = <String>[
    'package:talker/',
    'package:logging/',
    'package:sentry/',
    'package:firebase_crashlytics/',
  ];
  final files = <File>[
    File('pubspec.yaml'),
    ...Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
  ];

  final offenders = <String>[];
  for (final file in files) {
    final source = file.readAsStringSync();
    for (final dependency in forbiddenExternalLoggers) {
      if (source.contains(dependency)) {
        offenders.add('${file.path}: $dependency');
      }
    }
  }

  expect(offenders, isEmpty);
});
```

Keep the existing `blocpod_arch` prohibition. This test verifies the current dependency boundary without claiming to enumerate every future SDK.

- [ ] **Step 2: Run the guard test before metadata edits**

Run:

```bash
cd packages/logger && flutter test test/dependency_direction_test.dart
```

Expected: PASS, establishing the baseline; it must remain green after all metadata and documentation edits.

- [ ] **Step 3: Update package versions and descriptions**

Set exact values:

```yaml
# packages/logger/pubspec.yaml
version: 0.2.0
description: Generic structured log entries, sinks, and JSON/pretty encoders for Blocpod packages.

# packages/arch_logger/pubspec.yaml
version: 0.3.0
dependencies:
  blocpod_arch: ^0.3.0
  blocpod_logger: ^0.2.0

# packages/sample/pubspec.yaml
dependencies:
  blocpod_arch: ^0.3.0
  blocpod_arch_logger: ^0.3.0
  blocpod_logger: ^0.2.0
```

Run `flutter pub get` at the workspace root and include `pubspec.lock` only if it changes.

- [ ] **Step 4: Document the logger migration and adapter boundary**

Add a `0.2.0` changelog section stating:

```markdown
## 0.2.0

- Changed `DebugPrintLogSink` and `formatBlocpodLogEntry` to emit versioned JSON Lines by default.
- Added `BlocpodLogEncoder`, `JsonLogEncoder`, `PrettyLogEncoder`, and `PrettyLogDetail`.
- Replaced `BlocpodLogEntry.metadata` with `attributes` and dedicated sequence/trace fields.
- Removed automatic key-based redaction; applications and external sink adapters now own sensitive-data policy.
```

In the logger README, show one JSON-default example and one `DebugPrintLogSink(encoder: const PrettyLogEncoder())` example. Show a minimal `TalkerLogSink implements BlocpodLogSink` pseudocode example that maps fields directly, label it application-owned, and state that no `UserProvidedLogSink` class is exported.

In the arch logger README, show `PrettyLogEncoder` together with `PrettyEventLogRecordFormatter`. Explain `recordSequence → sequence`, dedicated trace fields, and nested `eventMetadata` / `stateMetadata`.

In root/sample docs, update package summaries and sample visible output. Remove all claims that Blocpod automatically redacts keys or that pretty messages expose metadata key summaries.

- [ ] **Step 5: Search for stale API and release text**

Run:

```bash
rg -n "\.metadata|metadata:|redact|redaction|metadataKeys|recordSequence=|blocpod_logger: \^0\.1\.1|version: 0\.1\.1" packages/logger packages/arch_logger packages/sample README.md
```

Expected: no stale `BlocpodLogEntry.metadata` usage, old dependency constraint, old logger version, automatic-redaction promise, or metadata-key-summary promise. References to `EventLogRecord.metadata`, the migration sentence, and the explicit “no automatic redaction” contract are valid and should be inspected rather than blindly removed.

- [ ] **Step 6: Run package tests and commit release metadata/docs**

Run:

```bash
(cd packages/logger && flutter test)
(cd packages/arch_logger && flutter test)
(cd packages/sample && flutter test)
```

Expected: all PASS.

```bash
git add packages/logger/pubspec.yaml packages/arch_logger/pubspec.yaml packages/sample/pubspec.yaml packages/logger/test/dependency_direction_test.dart packages/logger/README.md packages/logger/CHANGELOG.md packages/arch_logger/README.md packages/arch_logger/CHANGELOG.md packages/sample/README.md README.md pubspec.lock
git commit -m "docs: prepare structured logging release"
```

If `pubspec.lock` is unchanged, omit it from `git add`.

---

### Task 9: Verify the complete release candidate

**Files:**
- Verify only; modify the smallest owning file if a command exposes a regression.

**Interfaces:**
- Verifies: every acceptance criterion in the approved spec and every workspace dependency boundary.

- [ ] **Step 1: Format and prove formatting is stable**

Run:

```bash
dart format --line-length 120 .
git diff --check
```

Expected: formatter completes and `git diff --check` emits no errors.

- [ ] **Step 2: Run the complete test matrix**

Run:

```bash
(cd packages/arch && flutter test)
(cd packages/logger && flutter test)
(cd packages/arch_logger && flutter test)
(cd packages/sample && flutter test)
```

Expected: all tests PASS. The arch suite is included to prove logger-envelope work did not alter FIFO observation, event-local outcomes, or trace attribution.

- [ ] **Step 3: Run workspace analysis**

Run:

```bash
flutter analyze
```

Expected: `No issues found!`.

- [ ] **Step 4: Inspect the final public and dependency surface**

Run:

```bash
dart pub workspace list
rg -n "export 'src/(blocpod_log_encoder|json_log_encoder|pretty_log_encoder)\.dart'" packages/logger/lib/blocpod_logger.dart
rg -n "talker|sentry|datadog|opentelemetry|firebase_crashlytics" packages/logger/lib packages/logger/pubspec.yaml packages/arch_logger/lib packages/arch_logger/pubspec.yaml
git status --short
git diff --stat 9bc49d4
```

Expected: all four workspace packages are listed; all three encoder exports exist; no external logging SDK appears in package source/dependencies; only intentional implementation changes are present.

- [ ] **Step 5: Record final verification evidence**

Capture the four passing test summaries, analyzer success line, `git diff --check` success, and final `git status --short` output in the implementation handoff. If any command fails, return to the task that owns the failing file, add a regression test there, and repeat this complete verification task after its focused fix commit.
