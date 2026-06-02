# Blocpod Riverpod Event Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Blocpod package workspace from the Riverpod event architecture design: core event architecture, standalone logging primitives, and the bridge logger adapter.

**Architecture:** `blocpod_arch` owns `Result`, `UseCase`, event dispatch, trace context, event log records, and the no-op logger provider while depending only on Flutter and `flutter_riverpod`. `blocpod_logger` owns generic sink and entry types without importing architecture primitives. `blocpod_arch_logger` maps `EventLogRecord` values to `BlocpodLogEntry` values and is the only package that depends on both sibling packages.

**Tech Stack:** Dart 3.11, Flutter, `flutter_riverpod` 3.3.1, `flutter_test`, package workspace packages.

---

## Scope Check

This plan covers the `blocpod` repository only. The Pit Wall migration in the design spec touches a separate application repository and should get its own implementation plan after all Blocpod package tests and docs pass here.

Run commands from the repository root unless a step explicitly starts with `cd packages/...`.

## File Structure

`packages/arch/lib/blocpod_arch.dart`
: Public barrel for the core package.

`packages/arch/lib/src/result.dart`
: Typed success/error result boundary used by repositories and use cases.

`packages/arch/lib/src/use_case.dart`
: Use case base class and `NoParams` marker.

`packages/arch/lib/src/event_controller.dart`
: `EventController`, `EventControllerNotifier`, dispatch lifecycle, and `Ref`/`WidgetRef` dispatch extensions.

`packages/arch/lib/src/trace_context.dart`
: Zone-backed trace and span correlation for nested dispatches.

`packages/arch/lib/src/event_log_record.dart`
: Structured event dispatch record and `AsyncValue` state-kind mapping.

`packages/arch/lib/src/event_logger.dart`
: `EventLogger`, `NoopEventLogger`, and `eventLoggerProvider`.

`packages/arch/test/result_use_case_test.dart`
: Result and use case contract tests.

`packages/arch/test/event_controller_test.dart`
: Dispatch routing and provider variant tests.

`packages/arch/test/event_logging_test.dart`
: Trace, logging, default no-op, and thrown-error tests.

`packages/arch/test/dependency_direction_test.dart`
: Guard that `blocpod_arch` never imports `blocpod_logger`.

`packages/logger/lib/blocpod_logger.dart`
: Public barrel for the logger package.

`packages/logger/lib/src/blocpod_log_level.dart`
: Log level enum.

`packages/logger/lib/src/blocpod_log_entry.dart`
: Generic structured log entry.

`packages/logger/lib/src/blocpod_log_sink.dart`
: Sink interface.

`packages/logger/lib/src/debug_print_log_sink.dart`
: Flutter `debugPrint` sink plus local formatting helper with metadata redaction.

`packages/logger/test/blocpod_logger_test.dart`
: Log entry and debug sink tests.

`packages/logger/test/dependency_direction_test.dart`
: Guard that `blocpod_logger` never imports `blocpod_arch`.

`packages/arch_logger/lib/blocpod_arch_logger.dart`
: Public barrel for the bridge package.

`packages/arch_logger/lib/src/blocpod_event_logger.dart`
: `EventLogger` implementation that writes formatted entries to a `BlocpodLogSink`.

`packages/arch_logger/lib/src/event_log_record_formatter.dart`
: Converts architecture event records into generic logger entries.

`packages/arch_logger/test/blocpod_arch_logger_test.dart`
: Bridge mapping and sink-error isolation tests.

`README.md`, `packages/*/README.md`, `docs/ARCHITECTURE.md`, `docs/ARCHITECTURE-ko.md`, `docs/CONVENTIONS.md`
: Documentation updated after implementation to match package APIs and dependency direction.

### Task 1: Core Result And UseCase API

**Files:**
- Create: `packages/arch/lib/src/result.dart`
- Create: `packages/arch/lib/src/use_case.dart`
- Modify: `packages/arch/lib/blocpod_arch.dart`
- Create: `packages/arch/test/result_use_case_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter_test/flutter_test.dart';

final class EchoUseCase extends UseCase<String, NoParams> {
  const EchoUseCase();

  @override
  Future<Result<String>> call(NoParams params) async {
    return const Result.ok('pong');
  }
}

void main() {
  test('Result exposes typed success and error branches', () {
    const success = Result<int>.ok(7);
    final failure = Exception('denied');
    final error = Result<int>.error(failure);

    expect(success, isA<Ok<int>>());
    expect((success as Ok<int>).value, 7);
    expect(success.toString(), 'Result<int>.ok(7)');

    expect(error, isA<Error<int>>());
    expect((error as Error<int>).error, same(failure));
    expect(error.toString(), 'Result<int>.error(Exception: denied)');
  });

  test('UseCase supports NoParams', () async {
    const useCase = EchoUseCase();

    final result = await useCase(const NoParams());

    expect(result, isA<Ok<String>>());
    expect((result as Ok<String>).value, 'pong');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd packages/arch && flutter test test/result_use_case_test.dart
```

Expected: FAIL because `Result`, `Ok`, `Error`, `UseCase`, and `NoParams` are not exported yet.

- [ ] **Step 3: Implement `Result<T>`**

Create `packages/arch/lib/src/result.dart`:

```dart
/// Result boundary for operations that can succeed or fail.
sealed class Result<T> {
  const Result();

  /// Creates a successful [Result] with [value].
  const factory Result.ok(T value) = Ok._;

  /// Creates an error [Result] with [error].
  const factory Result.error(Exception error) = Error._;
}

/// Successful [Result] branch.
final class Ok<T> extends Result<T> {
  const Ok._(this.value);

  /// Returned value.
  final T value;

  @override
  String toString() => 'Result<$T>.ok($value)';
}

/// Failed [Result] branch.
final class Error<T> extends Result<T> {
  const Error._(this.error);

  /// Returned failure.
  final Exception error;

  @override
  String toString() => 'Result<$T>.error($error)';
}
```

- [ ] **Step 4: Implement `UseCase` and `NoParams`**

Create `packages/arch/lib/src/use_case.dart`:

```dart
import 'result.dart';

/// Base interface for application use cases.
abstract class UseCase<Output, Params> {
  const UseCase();

  /// Executes the use case with [params].
  Future<Result<Output>> call(Params params);
}

/// Marker for use cases that do not require parameters.
final class NoParams {
  const NoParams();
}
```

- [ ] **Step 5: Export the public API**

Replace `packages/arch/lib/blocpod_arch.dart` with:

```dart
/// Core Riverpod event architecture package for Blocpod.
library;

export 'src/result.dart';
export 'src/use_case.dart';
```

- [ ] **Step 6: Run the focused test**

Run:

```bash
cd packages/arch && flutter test test/result_use_case_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/arch/lib packages/arch/test/result_use_case_test.dart
git commit -m "feat: add blocpod core result and use case"
```

### Task 2: Event Dispatch Boundary And Provider Variants

**Files:**
- Create: `packages/arch/lib/src/event_controller.dart`
- Modify: `packages/arch/lib/blocpod_arch.dart`
- Create: `packages/arch/test/event_controller_test.dart`

- [ ] **Step 1: Write the failing dispatch tests**

Create `packages/arch/test/event_controller_test.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class CounterEvent {
  const CounterEvent();
}

final class AddCounterEvent extends CounterEvent {
  const AddCounterEvent(this.amount);

  final int amount;
}

final counterProvider = AsyncNotifierProvider<CounterController, int>(CounterController.new);

final autoDisposeCounterProvider = AsyncNotifierProvider.autoDispose<CounterController, int>(
  CounterController.new,
);

final familyCounterProvider = AsyncNotifierProvider.family<FamilyCounterController, int, int>(
  FamilyCounterController.new,
);

final autoDisposeFamilyCounterProvider = AsyncNotifierProvider.autoDispose.family<FamilyCounterController, int, int>(
  FamilyCounterController.new,
);

final class CounterController extends EventControllerNotifier<int, CounterEvent> {
  @override
  Future<int> build() async {
    return 0;
  }

  @override
  Future<void> onEvent(CounterEvent event) async {
    switch (event) {
      case AddCounterEvent(:final amount):
        state = AsyncData(_currentValue + amount);
    }
  }

  int get _currentValue {
    return switch (state) {
      AsyncData(:final value) => value,
      _ => 0,
    };
  }
}

final class FamilyCounterController extends EventControllerNotifier<int, CounterEvent> {
  FamilyCounterController(this.initialValue);

  final int initialValue;

  @override
  Future<int> build() async {
    return initialValue;
  }

  @override
  Future<void> onEvent(CounterEvent event) async {
    switch (event) {
      case AddCounterEvent(:final amount):
        state = AsyncData(_currentValue + amount);
    }
  }

  int get _currentValue {
    return switch (state) {
      AsyncData(:final value) => value,
      _ => initialValue,
    };
  }
}

void main() {
  test('dispatch routes events to onEvent', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const AddCounterEvent(2));

    expect(container.read(counterProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 2));
  });

  test('Ref.dispatch supports regular and autoDispose providers', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final regularDispatchProvider = Provider<Future<void>>((ref) {
      return ref.dispatch(counterProvider, const AddCounterEvent(3));
    });
    final autoDisposeDispatchProvider = Provider<Future<void>>((ref) {
      return ref.dispatch(autoDisposeCounterProvider, const AddCounterEvent(4));
    });

    await container.read(regularDispatchProvider);
    await container.read(autoDisposeDispatchProvider);

    expect(container.read(counterProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 3));
    expect(
      container.read(autoDisposeCounterProvider),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 4),
    );
  });

  test('Ref.dispatch supports family and autoDispose.family providers', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final familyDispatchProvider = Provider<Future<void>>((ref) {
      return ref.dispatch(familyCounterProvider(10), const AddCounterEvent(5));
    });
    final autoDisposeFamilyDispatchProvider = Provider<Future<void>>((ref) {
      return ref.dispatch(autoDisposeFamilyCounterProvider(20), const AddCounterEvent(6));
    });

    await container.read(familyDispatchProvider);
    await container.read(autoDisposeFamilyDispatchProvider);

    expect(container.read(familyCounterProvider(10)), isA<AsyncData<int>>().having((value) => value.value, 'value', 15));
    expect(
      container.read(autoDisposeFamilyCounterProvider(20)),
      isA<AsyncData<int>>().having((value) => value.value, 'value', 26),
    );
  });

  testWidgets('WidgetRef.dispatch routes events through the same boundary', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    late WidgetRef widgetRef;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, child) {
            widgetRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await widgetRef.dispatch(counterProvider, const AddCounterEvent(8));

    expect(container.read(counterProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 8));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd packages/arch && flutter test test/event_controller_test.dart
```

Expected: FAIL because event controller types and dispatch extensions are missing.

- [ ] **Step 3: Implement the dispatch boundary**

Create `packages/arch/lib/src/event_controller.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Public dispatch boundary for event-driven controllers.
abstract class EventController<E> {
  /// Dispatches [event] through the controller.
  Future<void> dispatch(E event);
}

/// Riverpod [AsyncNotifier] base class with a single event dispatch boundary.
abstract class EventControllerNotifier<S, E> extends AsyncNotifier<S> implements EventController<E> {
  @override
  Future<void> dispatch(E event) async {
    await onEvent(event);
  }

  /// Handles one dispatched event.
  @protected
  Future<void> onEvent(E event);
}

/// Dispatch helper for providers and other non-widget Riverpod code.
extension RefEventDispatcherX on Ref {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) {
    return read(provider.notifier).dispatch(event);
  }
}

/// Dispatch helper for widgets.
extension WidgetRefEventDispatcherX on WidgetRef {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) {
    return read(provider.notifier).dispatch(event);
  }
}
```

- [ ] **Step 4: Export event controller APIs**

Replace `packages/arch/lib/blocpod_arch.dart` with:

```dart
/// Core Riverpod event architecture package for Blocpod.
library;

export 'src/event_controller.dart';
export 'src/result.dart';
export 'src/use_case.dart';
```

- [ ] **Step 5: Run the focused dispatch tests**

Run:

```bash
cd packages/arch && flutter test test/event_controller_test.dart
```

Expected: PASS.

- [ ] **Step 6: Run existing core tests**

Run:

```bash
cd packages/arch && flutter test
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/arch/lib packages/arch/test/event_controller_test.dart
git commit -m "feat: add riverpod event dispatch boundary"
```

### Task 3: Trace Context And Structured Event Logging

**Files:**
- Create: `packages/arch/lib/src/trace_context.dart`
- Create: `packages/arch/lib/src/event_log_record.dart`
- Create: `packages/arch/lib/src/event_logger.dart`
- Modify: `packages/arch/lib/src/event_controller.dart`
- Modify: `packages/arch/lib/blocpod_arch.dart`
- Create: `packages/arch/test/event_logging_test.dart`
- Create: `packages/arch/test/dependency_direction_test.dart`

- [ ] **Step 1: Write the failing event logging tests**

Create `packages/arch/test/event_logging_test.dart`:

```dart
import 'dart:async';

import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class LoggingEvent {
  const LoggingEvent();
}

final class IncrementEvent extends LoggingEvent {
  const IncrementEvent();
}

final class ThrowEvent extends LoggingEvent {
  const ThrowEvent();
}

final class ParentEvent extends LoggingEvent {
  const ParentEvent();
}

final class ChildEvent extends LoggingEvent {
  const ChildEvent();
}

final loggingProvider = AsyncNotifierProvider<LoggingController, int>(LoggingController.new);

final class LoggingController extends EventControllerNotifier<int, LoggingEvent> {
  @override
  Future<int> build() async {
    return 0;
  }

  @override
  Future<void> onEvent(LoggingEvent event) async {
    switch (event) {
      case IncrementEvent():
        final value = switch (state) {
          AsyncData(:final value) => value,
          _ => 0,
        };
        state = AsyncData(value + 1);
      case ThrowEvent():
        throw StateError('boom');
      case ParentEvent():
        await dispatch(const ChildEvent());
        state = const AsyncData(10);
      case ChildEvent():
        state = const AsyncData(5);
    }
  }

  @override
  Map<String, Object?> metadataFor(LoggingEvent event) {
    return switch (event) {
      IncrementEvent() => const {'kind': 'increment'},
      ThrowEvent() => const {'kind': 'throw'},
      ParentEvent() => const {'kind': 'parent'},
      ChildEvent() => const {'kind': 'child'},
    };
  }
}

final class CollectingEventLogger implements EventLogger {
  final records = <EventLogRecord>[];

  @override
  void log(EventLogRecord record) {
    records.add(record);
  }
}

final class ThrowingEventLogger implements EventLogger {
  @override
  void log(EventLogRecord record) {
    throw StateError('logger failed');
  }
}

void main() {
  test('default logger is no-op and dispatch still succeeds', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 1));
  });

  test('dispatch logs before and after AsyncValue state kinds', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [
        eventLoggerProvider.overrideWithValue(logger),
      ],
    );
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    expect(logger.records, hasLength(1));
    expect(logger.records.single.controllerName, 'LoggingController');
    expect(logger.records.single.eventName, 'IncrementEvent');
    expect(logger.records.single.beforeStateKind, AsyncValueKind.data);
    expect(logger.records.single.afterStateKind, AsyncValueKind.data);
    expect(logger.records.single.hasChanged, isTrue);
    expect(logger.records.single.metadata, containsPair('kind', 'increment'));
    expect(logger.records.single.error, isNull);
    expect(logger.records.single.stackTrace, isNull);
  });

  test('dispatch logs thrown errors and preserves the original stack trace', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [
        eventLoggerProvider.overrideWithValue(logger),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(loggingProvider.notifier).dispatch(const ThrowEvent()),
      throwsA(isA<StateError>()),
    );

    expect(logger.records, hasLength(1));
    expect(logger.records.single.eventName, 'ThrowEvent');
    expect(logger.records.single.error, isA<StateError>());
    expect(logger.records.single.stackTrace, isNotNull);
  });

  test('nested dispatches keep one trace id and create child spans', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(
      overrides: [
        eventLoggerProvider.overrideWithValue(logger),
      ],
    );
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const ParentEvent());

    final parent = logger.records.singleWhere((record) => record.eventName == 'ParentEvent');
    final child = logger.records.singleWhere((record) => record.eventName == 'ChildEvent');

    expect(child.traceContext.traceId, parent.traceContext.traceId);
    expect(parent.traceContext.parentSpanId, isNull);
    expect(child.traceContext.parentSpanId, parent.traceContext.spanId);
    expect(child.traceContext.spanId, isNot(parent.traceContext.spanId));
  });

  test('logger failures do not break application flow', () async {
    final container = ProviderContainer(
      overrides: [
        eventLoggerProvider.overrideWithValue(ThrowingEventLogger()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(loggingProvider.notifier).dispatch(const IncrementEvent());

    expect(container.read(loggingProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 1));
  });

  test('TraceContext.run exposes current context only inside the async zone', () async {
    final context = TraceContext.root(startedAt: DateTime.utc(2026, 6));

    expect(TraceContext.current, isNull);
    await TraceContext.run(context, () async {
      await Future<void>.delayed(Duration.zero);
      expect(TraceContext.current, same(context));
    });
    expect(TraceContext.current, isNull);
  });
}
```

- [ ] **Step 2: Write the dependency direction test**

Create `packages/arch/test/dependency_direction_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocpod_arch does not import blocpod_logger', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      if (source.contains('package:blocpod_logger/')) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run:

```bash
cd packages/arch && flutter test test/event_logging_test.dart test/dependency_direction_test.dart
```

Expected: FAIL because trace, log record, logger APIs, and `metadataFor` are missing.

- [ ] **Step 4: Implement `TraceContext`**

Create `packages/arch/lib/src/trace_context.dart`:

```dart
import 'dart:async';

/// Correlation context for one event dispatch span.
final class TraceContext {
  const TraceContext({
    required this.traceId,
    required this.spanId,
    required this.parentSpanId,
    required this.startedAt,
  });

  static const Object _zoneKey = #blocpodTraceContext;
  static int _sequence = 0;

  /// Current trace context for this async zone.
  static TraceContext? get current => Zone.current[_zoneKey] as TraceContext?;

  /// Creates a root trace context.
  static TraceContext root({DateTime? startedAt}) {
    return TraceContext(
      traceId: _nextId('trace'),
      spanId: _nextId('span'),
      parentSpanId: null,
      startedAt: startedAt ?? DateTime.now(),
    );
  }

  /// Runs [body] with [context] available through [current].
  static R run<R>(TraceContext context, R Function() body) {
    return runZoned(body, zoneValues: {_zoneKey: context});
  }

  /// Creates a child span under this trace.
  TraceContext child({DateTime? startedAt}) {
    return TraceContext(
      traceId: traceId,
      spanId: _nextId('span'),
      parentSpanId: spanId,
      startedAt: startedAt ?? DateTime.now(),
    );
  }

  /// Shared trace identifier.
  final String traceId;

  /// Span identifier for this dispatch.
  final String spanId;

  /// Parent span identifier for nested dispatches.
  final String? parentSpanId;

  /// Start time for this dispatch span.
  final DateTime startedAt;

  static String _nextId(String prefix) {
    _sequence += 1;
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$_sequence';
  }
}
```

- [ ] **Step 5: Implement event log record types**

Create `packages/arch/lib/src/event_log_record.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trace_context.dart';

/// Coarse state kind for an [AsyncValue] without storing state payloads.
enum AsyncValueKind {
  /// The provider is loading.
  loading,

  /// The provider has data.
  data,

  /// The provider has an error.
  error,
}

/// Structured record emitted for one event dispatch.
final class EventLogRecord {
  const EventLogRecord({
    required this.traceContext,
    required this.controllerName,
    required this.eventName,
    required this.startedAt,
    required this.duration,
    required this.beforeStateKind,
    required this.afterStateKind,
    required this.hasChanged,
    this.error,
    this.stackTrace,
    this.metadata = const <String, Object?>{},
  });

  /// Trace context for this dispatch.
  final TraceContext traceContext;

  /// Runtime controller name.
  final String controllerName;

  /// Runtime event name.
  final String eventName;

  /// Dispatch start time.
  final DateTime startedAt;

  /// Dispatch duration.
  final Duration duration;

  /// State kind before handling the event.
  final AsyncValueKind beforeStateKind;

  /// State kind after handling the event.
  final AsyncValueKind afterStateKind;

  /// Whether the controller's [AsyncValue] changed.
  final bool hasChanged;

  /// Error thrown by the event handler.
  final Object? error;

  /// Stack trace captured with [error].
  final StackTrace? stackTrace;

  /// Sanitized metadata supplied by the controller.
  final Map<String, Object?> metadata;
}

/// Maps an [AsyncValue] to a payload-free state kind.
AsyncValueKind asyncValueKindOf<S>(AsyncValue<S> value) {
  return switch (value) {
    AsyncLoading<S>() => AsyncValueKind.loading,
    AsyncError<S>() => AsyncValueKind.error,
    AsyncData<S>() => AsyncValueKind.data,
  };
}
```

- [ ] **Step 6: Implement logger contract and provider**

Create `packages/arch/lib/src/event_logger.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_log_record.dart';

/// Receives structured event dispatch records.
abstract interface class EventLogger {
  /// Logs [record].
  void log(EventLogRecord record);
}

/// Logger implementation that intentionally does nothing.
final class NoopEventLogger implements EventLogger {
  const NoopEventLogger();

  @override
  void log(EventLogRecord record) {}
}

/// Provider used by event controllers to emit records.
final eventLoggerProvider = Provider<EventLogger>((ref) {
  return const NoopEventLogger();
});
```

- [ ] **Step 7: Wire logging into dispatch**

Replace `packages/arch/lib/src/event_controller.dart` with:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_log_record.dart';
import 'event_logger.dart';
import 'trace_context.dart';

/// Public dispatch boundary for event-driven controllers.
abstract class EventController<E> {
  /// Dispatches [event] through the controller.
  Future<void> dispatch(E event);
}

/// Riverpod [AsyncNotifier] base class with a single event dispatch boundary.
abstract class EventControllerNotifier<S, E> extends AsyncNotifier<S> implements EventController<E> {
  @override
  Future<void> dispatch(E event) async {
    final before = state;
    final startedAt = DateTime.now();
    final parentTrace = TraceContext.current;
    final traceContext = parentTrace == null ? TraceContext.root(startedAt: startedAt) : parentTrace.child(startedAt: startedAt);

    Object? thrownError;
    StackTrace? thrownStackTrace;

    try {
      await TraceContext.run(traceContext, () async {
        await onEvent(event);
      });
    } catch (error, stackTrace) {
      thrownError = error;
      thrownStackTrace = stackTrace;
      rethrow;
    } finally {
      final after = state;
      final finishedAt = DateTime.now();
      final record = EventLogRecord(
        traceContext: traceContext,
        controllerName: controllerName,
        eventName: eventName(event),
        startedAt: startedAt,
        duration: finishedAt.difference(startedAt),
        beforeStateKind: asyncValueKindOf(before),
        afterStateKind: asyncValueKindOf(after),
        hasChanged: before != after,
        error: thrownError,
        stackTrace: thrownStackTrace,
        metadata: metadataFor(event),
      );

      _logSafely(record);
    }
  }

  /// Handles one dispatched event.
  @protected
  Future<void> onEvent(E event);

  /// Name written to [EventLogRecord.controllerName].
  @protected
  String get controllerName => runtimeType.toString();

  /// Name written to [EventLogRecord.eventName].
  @protected
  String eventName(E event) => event.runtimeType.toString();

  /// Sanitized metadata for [event].
  @protected
  Map<String, Object?> metadataFor(E event) => const <String, Object?>{};

  void _logSafely(EventLogRecord record) {
    try {
      ref.read(eventLoggerProvider).log(record);
    } catch (_) {
      // Logging must not break controller flow.
    }
  }
}

/// Dispatch helper for providers and other non-widget Riverpod code.
extension RefEventDispatcherX on Ref {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) {
    return read(provider.notifier).dispatch(event);
  }
}

/// Dispatch helper for widgets.
extension WidgetRefEventDispatcherX on WidgetRef {
  /// Reads [provider]'s notifier and dispatches [event].
  Future<void> dispatch<N extends EventControllerNotifier<S, E>, S, E>(
    AsyncNotifierProvider<N, S> provider,
    E event,
  ) {
    return read(provider.notifier).dispatch(event);
  }
}
```

- [ ] **Step 8: Export trace and logging APIs**

Replace `packages/arch/lib/blocpod_arch.dart` with:

```dart
/// Core Riverpod event architecture package for Blocpod.
library;

export 'src/event_controller.dart';
export 'src/event_log_record.dart';
export 'src/event_logger.dart';
export 'src/result.dart';
export 'src/trace_context.dart';
export 'src/use_case.dart';
```

- [ ] **Step 9: Run focused logging tests**

Run:

```bash
cd packages/arch && flutter test test/event_logging_test.dart test/dependency_direction_test.dart
```

Expected: PASS.

- [ ] **Step 10: Run all core package tests**

Run:

```bash
cd packages/arch && flutter test
```

Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add packages/arch/lib packages/arch/test
git commit -m "feat: add event trace logging contracts"
```

### Task 4: Generic Logger Package

**Files:**
- Modify: `packages/logger/pubspec.yaml`
- Modify: `packages/logger/lib/blocpod_logger.dart`
- Create: `packages/logger/lib/src/blocpod_log_level.dart`
- Create: `packages/logger/lib/src/blocpod_log_entry.dart`
- Create: `packages/logger/lib/src/blocpod_log_sink.dart`
- Create: `packages/logger/lib/src/debug_print_log_sink.dart`
- Create: `packages/logger/test/blocpod_logger_test.dart`
- Create: `packages/logger/test/dependency_direction_test.dart`

- [ ] **Step 1: Write the failing logger tests**

Create `packages/logger/test/blocpod_logger_test.dart`:

```dart
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BlocpodLogEntry preserves structured fields', () {
    final error = StateError('failed');
    final stackTrace = StackTrace.current;
    final timestamp = DateTime.utc(2026, 6);

    final entry = BlocpodLogEntry(
      level: BlocpodLogLevel.warning,
      message: 'dispatch finished',
      timestamp: timestamp,
      metadata: const {'traceId': 'trace-1'},
      error: error,
      stackTrace: stackTrace,
    );

    expect(entry.level, BlocpodLogLevel.warning);
    expect(entry.message, 'dispatch finished');
    expect(entry.timestamp, timestamp);
    expect(entry.metadata, containsPair('traceId', 'trace-1'));
    expect(entry.error, same(error));
    expect(entry.stackTrace, same(stackTrace));
  });

  test('DebugPrintLogSink formats local development output', () {
    final messages = <String>[];
    final sink = DebugPrintLogSink(
      debugPrintOverride: (message, {wrapWidth}) {
        messages.add(message ?? '');
      },
    );

    sink.write(
      BlocpodLogEntry(
        level: BlocpodLogLevel.info,
        message: 'CounterController IncrementEvent data->data',
        timestamp: DateTime.utc(2026, 6, 1, 9, 30),
        metadata: const {
          'traceId': 'trace-1',
          'durationMicros': 1200,
        },
      ),
    );

    expect(messages, hasLength(1));
    expect(messages.single, contains('[info]'));
    expect(messages.single, contains('2026-06-01T09:30:00.000Z'));
    expect(messages.single, contains('CounterController IncrementEvent data->data'));
    expect(messages.single, contains('traceId=trace-1'));
    expect(messages.single, contains('durationMicros=1200'));
  });

  test('formatting does not print sensitive metadata by default', () {
    final formatted = formatBlocpodLogEntry(
      BlocpodLogEntry(
        level: BlocpodLogLevel.error,
        message: 'failed',
        timestamp: DateTime.utc(2026, 6),
        metadata: const {
          'token': 'abc',
          'secretKey': 'hidden',
          'credentialId': 'cred',
          'password': 'pw',
          'traceId': 'trace-1',
        },
      ),
    );

    expect(formatted, contains('traceId=trace-1'));
    expect(formatted, isNot(contains('abc')));
    expect(formatted, isNot(contains('hidden')));
    expect(formatted, isNot(contains('cred')));
    expect(formatted, isNot(contains('pw')));
  });
}
```

Create `packages/logger/test/dependency_direction_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocpod_logger does not import blocpod_arch', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      if (source.contains('package:blocpod_arch/')) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
cd packages/logger && flutter test
```

Expected: FAIL because logger APIs and Flutter test dependencies are missing.

- [ ] **Step 3: Update package dependencies for `debugPrint`**

Replace `packages/logger/pubspec.yaml` with:

```yaml
name: blocpod_logger
description: Generic logging primitives for Blocpod.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.11.5

resolution: workspace

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
```

- [ ] **Step 4: Implement log level**

Create `packages/logger/lib/src/blocpod_log_level.dart`:

```dart
/// Severity for Blocpod log entries.
enum BlocpodLogLevel {
  /// Fine-grained development detail.
  debug,

  /// Informational event.
  info,

  /// Recoverable warning.
  warning,

  /// Error event.
  error,
}
```

- [ ] **Step 5: Implement log entry**

Create `packages/logger/lib/src/blocpod_log_entry.dart`:

```dart
import 'blocpod_log_level.dart';

/// Generic structured log entry emitted by Blocpod log sinks.
final class BlocpodLogEntry {
  const BlocpodLogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.metadata = const <String, Object?>{},
    this.error,
    this.stackTrace,
  });

  /// Entry severity.
  final BlocpodLogLevel level;

  /// Human-readable message.
  final String message;

  /// Entry timestamp.
  final DateTime timestamp;

  /// Structured metadata.
  final Map<String, Object?> metadata;

  /// Associated error.
  final Object? error;

  /// Associated stack trace.
  final StackTrace? stackTrace;
}
```

- [ ] **Step 6: Implement sink interface**

Create `packages/logger/lib/src/blocpod_log_sink.dart`:

```dart
import 'blocpod_log_entry.dart';

/// Output sink for Blocpod log entries.
abstract interface class BlocpodLogSink {
  /// Writes [entry].
  void write(BlocpodLogEntry entry);
}
```

- [ ] **Step 7: Implement debug print sink and formatter**

Create `packages/logger/lib/src/debug_print_log_sink.dart`:

```dart
import 'package:flutter/foundation.dart';

import 'blocpod_log_entry.dart';
import 'blocpod_log_sink.dart';

/// Log sink that writes formatted entries through Flutter's [debugPrint].
final class DebugPrintLogSink implements BlocpodLogSink {
  DebugPrintLogSink({DebugPrintCallback? debugPrintOverride}) : _debugPrint = debugPrintOverride ?? debugPrint;

  final DebugPrintCallback _debugPrint;

  @override
  void write(BlocpodLogEntry entry) {
    _debugPrint(formatBlocpodLogEntry(entry));
  }
}

/// Formats [entry] for local development logs.
String formatBlocpodLogEntry(BlocpodLogEntry entry) {
  final metadata = _safeMetadata(entry.metadata);
  final metadataText = metadata.entries.map((entry) => '${entry.key}=${entry.value}').join(' ');
  final buffer = StringBuffer()
    ..write('[${entry.level.name}] ')
    ..write(entry.timestamp.toUtc().toIso8601String())
    ..write(' ')
    ..write(entry.message);

  if (metadataText.isNotEmpty) {
    buffer
      ..write(' ')
      ..write(metadataText);
  }

  if (entry.error != null) {
    buffer
      ..write(' error=')
      ..write(entry.error);
  }

  return buffer.toString();
}

Map<String, Object?> _safeMetadata(Map<String, Object?> metadata) {
  final safe = <String, Object?>{};
  for (final MapEntry(:key, :value) in metadata.entries) {
    final normalized = key.toLowerCase();
    final isSensitive = normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('credential') ||
        normalized.contains('password');

    if (!isSensitive) {
      safe[key] = value;
    }
  }

  return safe;
}
```

- [ ] **Step 8: Export logger APIs**

Replace `packages/logger/lib/blocpod_logger.dart` with:

```dart
/// Generic logging primitives for Blocpod.
library;

export 'src/blocpod_log_entry.dart';
export 'src/blocpod_log_level.dart';
export 'src/blocpod_log_sink.dart';
export 'src/debug_print_log_sink.dart';
```

- [ ] **Step 9: Run logger tests**

Run:

```bash
cd packages/logger && flutter test
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add packages/logger/pubspec.yaml packages/logger/lib packages/logger/test
git commit -m "feat: add blocpod logger primitives"
```

### Task 5: Architecture Logger Bridge

**Files:**
- Modify: `packages/arch_logger/pubspec.yaml`
- Modify: `packages/arch_logger/lib/blocpod_arch_logger.dart`
- Create: `packages/arch_logger/lib/src/event_log_record_formatter.dart`
- Create: `packages/arch_logger/lib/src/blocpod_event_logger.dart`
- Create: `packages/arch_logger/test/blocpod_arch_logger_test.dart`

- [ ] **Step 1: Write the failing bridge tests**

Create `packages/arch_logger/test/blocpod_arch_logger_test.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter_test/flutter_test.dart';

final class MemoryLogSink implements BlocpodLogSink {
  final entries = <BlocpodLogEntry>[];

  @override
  void write(BlocpodLogEntry entry) {
    entries.add(entry);
  }
}

final class ThrowingLogSink implements BlocpodLogSink {
  @override
  void write(BlocpodLogEntry entry) {
    throw StateError('sink failed');
  }
}

EventLogRecord eventRecord({
  Object? error,
  StackTrace? stackTrace,
}) {
  return EventLogRecord(
    traceContext: TraceContext(
      traceId: 'trace-1',
      spanId: 'span-1',
      parentSpanId: 'parent-1',
      startedAt: DateTime.utc(2026, 6, 1, 9, 30),
    ),
    controllerName: 'CounterController',
    eventName: 'IncrementEvent',
    startedAt: DateTime.utc(2026, 6, 1, 9, 30),
    duration: const Duration(milliseconds: 12),
    beforeStateKind: AsyncValueKind.loading,
    afterStateKind: AsyncValueKind.data,
    hasChanged: true,
    error: error,
    stackTrace: stackTrace,
    metadata: const {'feature': 'counter'},
  );
}

void main() {
  test('BlocpodEventLogger maps EventLogRecord into BlocpodLogEntry', () {
    final sink = MemoryLogSink();
    final logger = BlocpodEventLogger(sink);

    logger.log(eventRecord());

    expect(sink.entries, hasLength(1));
    final entry = sink.entries.single;
    expect(entry.level, BlocpodLogLevel.info);
    expect(entry.message, 'CounterController IncrementEvent loading->data 12ms');
    expect(entry.timestamp, DateTime.utc(2026, 6, 1, 9, 30));
    expect(entry.metadata, containsPair('traceId', 'trace-1'));
    expect(entry.metadata, containsPair('spanId', 'span-1'));
    expect(entry.metadata, containsPair('parentSpanId', 'parent-1'));
    expect(entry.metadata, containsPair('controllerName', 'CounterController'));
    expect(entry.metadata, containsPair('eventName', 'IncrementEvent'));
    expect(entry.metadata, containsPair('durationMicros', 12000));
    expect(entry.metadata, containsPair('beforeStateKind', 'loading'));
    expect(entry.metadata, containsPair('afterStateKind', 'data'));
    expect(entry.metadata, containsPair('hasChanged', true));
    expect(entry.metadata, containsPair('feature', 'counter'));
    expect(entry.error, isNull);
    expect(entry.stackTrace, isNull);
  });

  test('error records map to error-level log entries', () {
    final sink = MemoryLogSink();
    final logger = BlocpodEventLogger(sink);
    final error = StateError('boom');
    final stackTrace = StackTrace.current;

    logger.log(eventRecord(error: error, stackTrace: stackTrace));

    final entry = sink.entries.single;
    expect(entry.level, BlocpodLogLevel.error);
    expect(entry.error, same(error));
    expect(entry.stackTrace, same(stackTrace));
  });

  test('sink failures are isolated', () {
    final logger = BlocpodEventLogger(ThrowingLogSink());

    expect(() => logger.log(eventRecord()), returnsNormally);
  });
}
```

- [ ] **Step 2: Run the bridge tests to verify they fail**

Run:

```bash
cd packages/arch_logger && flutter test
```

Expected: FAIL because bridge APIs and Flutter test dependencies are missing.

- [ ] **Step 3: Update test dependency**

Replace `packages/arch_logger/pubspec.yaml` with:

```yaml
name: blocpod_arch_logger
description: Bridge adapter between blocpod_arch event records and blocpod_logger sinks.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.11.5

resolution: workspace

dependencies:
  blocpod_arch:
    path: ../arch
  blocpod_logger:
    path: ../logger

dev_dependencies:
  flutter_test:
    sdk: flutter
```

- [ ] **Step 4: Implement formatter**

Create `packages/arch_logger/lib/src/event_log_record_formatter.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';

/// Converts Blocpod architecture event records into generic log entries.
final class EventLogRecordFormatter {
  const EventLogRecordFormatter();

  /// Formats [record].
  BlocpodLogEntry format(EventLogRecord record) {
    final beforeKind = record.beforeStateKind.name;
    final afterKind = record.afterStateKind.name;

    return BlocpodLogEntry(
      level: record.error == null ? BlocpodLogLevel.info : BlocpodLogLevel.error,
      message: '${record.controllerName} ${record.eventName} $beforeKind->$afterKind ${record.duration.inMilliseconds}ms',
      timestamp: record.startedAt,
      metadata: <String, Object?>{
        'traceId': record.traceContext.traceId,
        'spanId': record.traceContext.spanId,
        if (record.traceContext.parentSpanId != null) 'parentSpanId': record.traceContext.parentSpanId,
        'controllerName': record.controllerName,
        'eventName': record.eventName,
        'durationMicros': record.duration.inMicroseconds,
        'beforeStateKind': beforeKind,
        'afterStateKind': afterKind,
        'hasChanged': record.hasChanged,
        ...record.metadata,
      },
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }
}
```

- [ ] **Step 5: Implement event logger adapter**

Create `packages/arch_logger/lib/src/blocpod_event_logger.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';

import 'event_log_record_formatter.dart';

/// [EventLogger] implementation backed by a [BlocpodLogSink].
final class BlocpodEventLogger implements EventLogger {
  const BlocpodEventLogger(
    this.sink, {
    this.formatter = const EventLogRecordFormatter(),
  });

  /// Target log sink.
  final BlocpodLogSink sink;

  /// Record formatter.
  final EventLogRecordFormatter formatter;

  @override
  void log(EventLogRecord record) {
    try {
      sink.write(formatter.format(record));
    } catch (_) {
      // Sink failures must not break application flow.
    }
  }
}
```

- [ ] **Step 6: Export bridge APIs**

Replace `packages/arch_logger/lib/blocpod_arch_logger.dart` with:

```dart
/// Bridge adapter between Blocpod architecture events and Blocpod log sinks.
library;

export 'src/blocpod_event_logger.dart';
export 'src/event_log_record_formatter.dart';
```

- [ ] **Step 7: Run bridge tests**

Run:

```bash
cd packages/arch_logger && flutter test
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add packages/arch_logger/pubspec.yaml packages/arch_logger/lib packages/arch_logger/test
git commit -m "feat: add blocpod architecture logger bridge"
```

### Task 6: Documentation And Workspace Verification

**Files:**
- Modify: `README.md`
- Modify: `packages/arch/README.md`
- Modify: `packages/logger/README.md`
- Modify: `packages/arch_logger/README.md`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/ARCHITECTURE-ko.md`
- Modify: `docs/CONVENTIONS.md`
- Modify: `pubspec.lock`

- [ ] **Step 1: Update dependency resolution**

Run:

```bash
flutter pub get
```

Expected: updates `pubspec.lock` if dependency graph changed.

- [ ] **Step 2: Update root README design link and API summary**

Replace the design sentence and package bullets in `README.md` with:

```markdown
The workspace starts from the design in [docs/superpowers/specs/2026-06-01-blocpod-riverpod-event-architecture-design.md](docs/superpowers/specs/2026-06-01-blocpod-riverpod-event-architecture-design.md).

## Packages

- `packages/arch` (`blocpod_arch`): `Result`, `UseCase`, `EventControllerNotifier`, dispatch extensions, trace context, event records, and no-op event logger provider.
- `packages/logger` (`blocpod_logger`): generic log entries, log levels, log sinks, debug print output, and local-development formatting.
- `packages/arch_logger` (`blocpod_arch_logger`): `EventLogger` adapter that maps `EventLogRecord` values to `BlocpodLogEntry` values.
```

Replace the local commands block in `README.md` with:

````markdown
## Local Commands

```sh
flutter pub get
dart pub workspace list
cd packages/arch && flutter test
cd packages/logger && flutter test
cd packages/arch_logger && flutter test
flutter analyze
dart format --line-length 120 .
```
````

- [ ] **Step 3: Update package README files**

Replace `packages/arch/README.md` with:

```markdown
# blocpod_arch

Core Riverpod event architecture package for Blocpod.

This package owns:

- `Result<T>`, `Ok<T>`, and `Error<T>`
- `UseCase<Output, Params>` and `NoParams`
- `EventController<E>` and `EventControllerNotifier<S, E>`
- `RefEventDispatcherX` and `WidgetRefEventDispatcherX`
- `TraceContext`
- `EventLogRecord` and `AsyncValueKind`
- `EventLogger`, `NoopEventLogger`, and `eventLoggerProvider`

`blocpod_arch` depends on Flutter and `flutter_riverpod`. It must not depend on `blocpod_logger` or any concrete logging sink.
```

Replace `packages/logger/README.md` with:

```markdown
# blocpod_logger

Generic logging primitives for Blocpod.

This package owns:

- `BlocpodLogLevel`
- `BlocpodLogEntry`
- `BlocpodLogSink`
- `DebugPrintLogSink`
- `formatBlocpodLogEntry`

`blocpod_logger` may use Flutter's `debugPrint` for local-development output. It must not import `blocpod_arch`.
```

Replace `packages/arch_logger/README.md` with:

```markdown
# blocpod_arch_logger

Bridge adapter between `blocpod_arch` event records and `blocpod_logger` sinks.

This package owns:

- `EventLogRecordFormatter`
- `BlocpodEventLogger`

`blocpod_arch_logger` is the only package in this workspace that should depend on both `blocpod_arch` and `blocpod_logger`.
```

- [ ] **Step 4: Align architecture docs**

In `docs/ARCHITECTURE.md`, replace the `Core Architecture Source Contract` section with:

````markdown
## Core Architecture Source Contract

Blocpod's architecture source contract lives in the workspace packages:

1. `packages/arch/lib/src/result.dart`
2. `packages/arch/lib/src/use_case.dart`
3. `packages/arch/lib/src/event_controller.dart`
4. `packages/arch/lib/src/trace_context.dart`
5. `packages/arch/lib/src/event_log_record.dart`
6. `packages/arch/lib/src/event_logger.dart`
7. `packages/logger/lib/src/`
8. `packages/arch_logger/lib/src/`

Applications import the stable public barrels:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
```

The dependency direction is fixed:

- `blocpod_arch` depends on Flutter and `flutter_riverpod`.
- `blocpod_logger` depends on Flutter for `debugPrint` output.
- `blocpod_arch_logger` depends on `blocpod_arch` and `blocpod_logger`.
- `blocpod_arch` must not import `blocpod_logger`.
- `blocpod_logger` must not import `blocpod_arch`.

Controllers inherit `EventControllerNotifier<State, Event>` and expose only `dispatch` as their public action API. Widgets dispatch events with `ref.dispatch(provider, event)`. Do not create generated `@riverpod` controller classes for this architecture.
````

Replace the matching source-contract section in `docs/ARCHITECTURE-ko.md` with:

````markdown
## 핵심 아키텍처 소스 계약

Blocpod의 아키텍처 소스 계약은 워크스페이스 패키지에 둔다.

1. `packages/arch/lib/src/result.dart`
2. `packages/arch/lib/src/use_case.dart`
3. `packages/arch/lib/src/event_controller.dart`
4. `packages/arch/lib/src/trace_context.dart`
5. `packages/arch/lib/src/event_log_record.dart`
6. `packages/arch/lib/src/event_logger.dart`
7. `packages/logger/lib/src/`
8. `packages/arch_logger/lib/src/`

애플리케이션은 안정적인 public barrel을 import한다.

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
```

의존성 방향은 고정한다.

- `blocpod_arch`는 Flutter와 `flutter_riverpod`에 의존한다.
- `blocpod_logger`는 `debugPrint` 출력용 Flutter에 의존한다.
- `blocpod_arch_logger`는 `blocpod_arch`와 `blocpod_logger`에 의존한다.
- `blocpod_arch`는 `blocpod_logger`를 import하지 않는다.
- `blocpod_logger`는 `blocpod_arch`를 import하지 않는다.

컨트롤러는 `EventControllerNotifier<State, Event>`를 상속하고 public action API로 `dispatch`만 노출한다. 위젯은 `ref.dispatch(provider, event)`로 이벤트를 전달한다. 이 아키텍처에서는 generated `@riverpod` controller class를 만들지 않는다.
````

- [ ] **Step 5: Align conventions docs**

In `docs/CONVENTIONS.md`, replace the `Logging` section with:

```markdown
## Logging

- Core event logging flows through `EventControllerNotifier.dispatch`.
- `blocpod_arch` emits `EventLogRecord` values through `eventLoggerProvider`.
- The default logger is `NoopEventLogger`.
- Applications install concrete logging through provider overrides, such as `BlocpodEventLogger(DebugPrintLogSink())`.
- Keep verbose or diagnostic metadata sanitized.
- Do not log secrets, tokens, credentials, passwords, or full raw payloads that may contain private data.
```

In `docs/CONVENTIONS.md`, replace the internal import example that uses `package:pit_wall/...` with:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
```

- [ ] **Step 6: Format all Dart files**

Run:

```bash
dart format --line-length 120 packages/arch packages/logger packages/arch_logger
```

Expected: formatted files with no syntax errors.

- [ ] **Step 7: Run all package tests**

Run:

```bash
cd packages/arch && flutter test
cd ../logger && flutter test
cd ../arch_logger && flutter test
```

Expected: all tests PASS.

- [ ] **Step 8: Run workspace analysis**

Run:

```bash
flutter analyze
```

Expected: no analyzer errors.

- [ ] **Step 9: Review the dependency graph manually**

Run:

```bash
rg -n "package:blocpod_logger/" packages/arch/lib packages/arch/test
rg -n "package:blocpod_arch/" packages/logger/lib packages/logger/test
```

Expected: first command prints no matches; second command prints no matches.

- [ ] **Step 10: Commit**

```bash
git add README.md docs/ARCHITECTURE.md docs/ARCHITECTURE-ko.md docs/CONVENTIONS.md packages/arch/README.md packages/logger/README.md packages/arch_logger/README.md pubspec.lock
git commit -m "docs: align blocpod architecture documentation"
```

## Final Verification

- [ ] **Step 1: Run complete verification from a clean shell**

```bash
flutter pub get
dart pub workspace list
cd packages/arch && flutter test
cd ../logger && flutter test
cd ../arch_logger && flutter test
cd ../..
flutter analyze
dart format --line-length 120 --set-exit-if-changed packages/arch packages/logger packages/arch_logger
```

Expected: dependency resolution succeeds, all tests pass, analyzer passes, and formatter reports no changed files.

- [ ] **Step 2: Confirm repository status**

```bash
git status -sb
```

Expected: clean working tree after the task commits, except for unrelated user-owned files that were already dirty before implementation.

## Self-Review Notes

Spec coverage:
- `blocpod_arch` public API, dispatch lifecycle, trace context, event records, no-op logger, logger provider, `Result`, and `UseCase` are covered by Tasks 1 through 3.
- `blocpod_logger` public API, debug output, and sensitive metadata redaction are covered by Task 4.
- `blocpod_arch_logger` record-to-entry mapping, error-level entries, and sink failure isolation are covered by Task 5.
- Dependency direction is covered by package dependencies, dependency direction tests, and manual `rg` verification.
- Pit Wall migration is intentionally split into a downstream plan because it is a separate application integration.

Placeholder scan:
- The plan contains concrete file paths, code snippets, commands, expected failures, expected passes, and commit messages.

Type consistency:
- `EventControllerNotifier<S, E>`, `AsyncNotifierProvider<N, S>`, `TraceContext`, `EventLogRecord`, `EventLogger`, `BlocpodLogEntry`, and `BlocpodEventLogger` signatures are consistent across tasks.
