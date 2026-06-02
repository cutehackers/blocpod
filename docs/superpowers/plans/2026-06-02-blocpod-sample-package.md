# Blocpod Sample Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a private Flutter sample package that demonstrates every public Blocpod feature through a small interactive app and focused tests.

**Architecture:** The sample package is a workspace consumer under `packages/sample`, not a dependency of the three Blocpod packages. It imports `blocpod_arch`, `blocpod_logger`, and `blocpod_arch_logger`, then shows event dispatch, use cases/results, provider variants, trace/logging metadata, and provider overrides in one runnable Flutter app. Production packages keep their existing dependency direction: only the sample and `blocpod_arch_logger` know both architecture and logger packages.

**Tech Stack:** Dart SDK `^3.11.5`, Flutter, `flutter_riverpod`, `blocpod_arch`, `blocpod_logger`, `blocpod_arch_logger`, `flutter_test`, `flutter_lints`.

---

## File Structure

- Modify `pubspec.yaml`
  - Add `packages/sample` to the root `workspace` list.
- Modify `README.md`
  - Add sample package commands and a feature map.
- Create `packages/sample/pubspec.yaml`
  - Private Flutter package with path dependencies on all Blocpod packages.
- Create `packages/sample/README.md`
  - Human-facing guide for what each sample file demonstrates.
- Create `packages/sample/lib/main.dart`
  - App entry point with `ProviderScope` and logger override.
- Create `packages/sample/lib/src/app.dart`
  - Main sample UI with counter, todo, provider-variant, and log panels.
- Create `packages/sample/lib/src/counter/counter_controller.dart`
  - `EventControllerNotifier<int, CounterEvent>` sample using direct dispatch, nested dispatch, event metadata, state labels, and state metadata.
- Create `packages/sample/lib/src/counter/counter_panel.dart`
  - Widget using `WidgetRef.dispatch`.
- Create `packages/sample/lib/src/todos/todo.dart`
  - Simple immutable todo model.
- Create `packages/sample/lib/src/todos/todo_use_cases.dart`
  - `UseCase` and `Result` examples.
- Create `packages/sample/lib/src/todos/todo_controller.dart`
  - Todo controller using `Result.ok` and `Result.error`.
- Create `packages/sample/lib/src/todos/todo_panel.dart`
  - Todo UI with success and failure actions.
- Create `packages/sample/lib/src/provider_variants/provider_variants.dart`
  - Regular, `autoDispose`, `family`, and `autoDispose.family` providers using the same controller pattern.
- Create `packages/sample/lib/src/provider_variants/provider_variants_panel.dart`
  - Small UI proving each provider variant supports dispatch.
- Create `packages/sample/lib/src/logging/in_memory_log_sink.dart`
  - `BlocpodLogSink` implementation that stores formatted `BlocpodLogEntry` values for UI and tests.
- Create `packages/sample/lib/src/logging/log_panel.dart`
  - Log UI showing phase, event name, trace ids, parent span ids, transitions, result, and sanitized metadata.
- Create `packages/sample/test/counter_controller_test.dart`
  - Controller and nested dispatch tests.
- Create `packages/sample/test/todo_controller_test.dart`
  - `UseCase`/`Result` and failure tests.
- Create `packages/sample/test/provider_variants_test.dart`
  - Regular, `autoDispose`, `family`, and `autoDispose.family` dispatch tests.
- Create `packages/sample/test/logging_test.dart`
  - Logger bridge and metadata tests.

## Design Constraints

- Do not add dependencies from `packages/arch` to `packages/logger` or from `packages/logger` to `packages/arch`.
- Keep the sample package `publish_to: none`.
- Avoid code generation. Use explicit `AsyncNotifierProvider` declarations to match the Blocpod architecture contract.
- Keep logs payload-free: show labels and metadata, not raw sensitive state payloads.
- Use small files by feature so a new reader can jump from UI action to controller behavior to log output.
- The sample must be executable with `cd packages/sample && flutter run` after `flutter pub get`.
- The first screen must be the working sample app, not a documentation or landing page.
- Every visible panel must map to one Blocpod concept and use short labels that match the source file names and README feature map.
- A new user must be able to understand the sample by following this path: run app -> press a panel button -> see state change -> see matching log entry -> open the feature map file.

## Acceptance Criteria

- `flutter run -d chrome` starts the sample without code changes or extra environment variables.
- The app shows counter, todo, provider variant, and event log panels on the first screen.
- Each panel has at least one action button that immediately demonstrates the concept it represents.
- The log panel updates when controller events are dispatched and exposes `phase`, `eventName`, `traceId`, `spanId`, optional `parentSpanId`, transition index, and `hasChanged` when present.
- `packages/sample/README.md` includes a feature map from visible panel to source file and a five-step usage flow.
- Root `README.md` includes sample run/test commands and links readers to the sample package.

---

### Task 1: Register The Sample Workspace Package

**Files:**
- Modify: `pubspec.yaml`
- Create: `packages/sample/pubspec.yaml`
- Create: `packages/sample/README.md`

- [ ] **Step 1: Add the package test target first**

Create `packages/sample/test/package_smoke_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample package is available', () {
    expect('blocpod_sample', isNotEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails before the package exists**

Run:

```sh
(cd packages/sample && flutter test test/package_smoke_test.dart)
```

Expected: FAIL because `packages/sample` does not exist.

- [ ] **Step 3: Add `packages/sample` to the root workspace**

Modify `pubspec.yaml`:

```yaml
workspace:
  - packages/arch
  - packages/logger
  - packages/arch_logger
  - packages/sample
```

- [ ] **Step 4: Create the sample package pubspec**

Create `packages/sample/pubspec.yaml`:

```yaml
name: blocpod_sample
description: Interactive sample app for Blocpod packages.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.11.5

resolution: workspace

dependencies:
  blocpod_arch:
    path: ../arch
  blocpod_arch_logger:
    path: ../arch_logger
  blocpod_logger:
    path: ../logger
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.3.1

dev_dependencies:
  flutter_lints: ^6.0.0
  flutter_test:
    sdk: flutter
```

- [ ] **Step 5: Create a short package README**

Create `packages/sample/README.md`:

````markdown
# Blocpod Sample

This private Flutter package demonstrates the Blocpod workspace packages:

- `blocpod_arch`: event controllers, dispatch helpers, use cases, results, trace context, and event records.
- `blocpod_logger`: generic log entries and sinks.
- `blocpod_arch_logger`: adapter from event records to log entries.

Run it with:

```sh
cd packages/sample
flutter run
```

Run tests with:

```sh
cd packages/sample
flutter test
```
````

- [ ] **Step 6: Fetch dependencies**

Run:

```sh
flutter pub get
dart pub workspace list
```

Expected: workspace list includes `blocpod_sample`.

- [ ] **Step 7: Run the package smoke test**

Run:

```sh
(cd packages/sample && flutter test test/package_smoke_test.dart)
```

Expected: PASS.

- [ ] **Step 8: Commit**

Run:

```sh
git add pubspec.yaml packages/sample/pubspec.yaml packages/sample/README.md packages/sample/test/package_smoke_test.dart
git commit -m "feat: add blocpod sample package"
```

---

### Task 2: Add The Counter Event Controller Sample

**Files:**
- Create: `packages/sample/lib/src/counter/counter_controller.dart`
- Create: `packages/sample/test/counter_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Create `packages/sample/test/counter_controller_test.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_sample/src/counter/counter_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class CollectingEventLogger implements EventLogger {
  final records = <EventLogRecord>[];

  @override
  void log(EventLogRecord record) {
    records.add(record);
  }
}

void main() {
  test('dispatch applies counter events', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterIncremented(2));
    await container.read(counterProvider.notifier).dispatch(const CounterDecremented());

    expect(container.read(counterProvider), isA<AsyncData<int>>().having((value) => value.value, 'value', 1));
  });

  test('nested dispatch creates parent and child trace spans', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterResetThroughChild());

    final completed = logger.records.where((record) => record.phase == EventLogPhase.eventCompleted).toList();
    final parent = completed.singleWhere((record) => record.eventName == 'CounterResetThroughChild');
    final child = completed.singleWhere((record) => record.eventName == 'CounterReset');

    expect(child.traceContext.traceId, parent.traceContext.traceId);
    expect(child.traceContext.parentSpanId, parent.traceContext.spanId);
  });

  test('metadata and state labels are payload-free', () async {
    final logger = CollectingEventLogger();
    final container = ProviderContainer(overrides: [eventLoggerProvider.overrideWithValue(logger)]);
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterIncremented(3));

    final transition = logger.records.singleWhere((record) => record.phase == EventLogPhase.transition);
    expect(transition.metadata, containsPair('amount', 3));
    expect(transition.previousStateLabel, 'count:0');
    expect(transition.nextStateLabel, 'count:3');
    expect(transition.stateMetadata, containsPair('changedBy', 3));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```sh
(cd packages/sample && flutter test test/counter_controller_test.dart)
```

Expected: FAIL because `counter_controller.dart` does not exist.

- [ ] **Step 3: Implement the counter controller**

Create `packages/sample/lib/src/counter/counter_controller.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class CounterEvent {
  const CounterEvent();
}

final class CounterIncremented extends CounterEvent {
  const CounterIncremented(this.amount);

  final int amount;
}

final class CounterDecremented extends CounterEvent {
  const CounterDecremented();
}

final class CounterReset extends CounterEvent {
  const CounterReset();
}

final class CounterResetThroughChild extends CounterEvent {
  const CounterResetThroughChild();
}

final counterProvider = AsyncNotifierProvider<CounterController, int>(CounterController.new);

final class CounterController extends EventControllerNotifier<int, CounterEvent> {
  @override
  Future<int> build() async => 0;

  @override
  Future<void> onEvent(CounterEvent event) async {
    switch (event) {
      case CounterIncremented(:final amount):
        state = AsyncData(_currentValue + amount);
      case CounterDecremented():
        state = AsyncData(_currentValue - 1);
      case CounterReset():
        state = const AsyncData(0);
      case CounterResetThroughChild():
        await dispatch(const CounterReset());
    }
  }

  @override
  String get controllerName => 'SampleCounterController';

  @override
  String eventName(CounterEvent event) => event.runtimeType.toString();

  @override
  Map<String, Object?> metadataFor(CounterEvent event) {
    return switch (event) {
      CounterIncremented(:final amount) => {'amount': amount},
      CounterDecremented() => const {'amount': -1},
      CounterReset() => const {'reason': 'direct-reset'},
      CounterResetThroughChild() => const {'reason': 'nested-dispatch'},
    };
  }

  @override
  String? stateLabel(AsyncValue<int> state) {
    return switch (state) {
      AsyncData(:final value) => 'count:$value',
      AsyncLoading<int>() => 'loading',
      AsyncError<int>() => 'error',
    };
  }

  @override
  Map<String, Object?> stateMetadata({required AsyncValue<int> previous, required AsyncValue<int> next}) {
    final previousValue = _valueOf(previous);
    final nextValue = _valueOf(next);
    if (previousValue == null || nextValue == null) {
      return const {};
    }
    return {'changedBy': nextValue - previousValue};
  }

  int get _currentValue => _valueOf(state) ?? 0;

  int? _valueOf(AsyncValue<int> value) {
    return switch (value) {
      AsyncData(:final value) => value,
      _ => null,
    };
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```sh
(cd packages/sample && flutter test test/counter_controller_test.dart)
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```sh
git add packages/sample/lib/src/counter/counter_controller.dart packages/sample/test/counter_controller_test.dart
git commit -m "feat: demonstrate blocpod counter dispatch"
```

---

### Task 3: Add UseCase And Result Todo Sample

**Files:**
- Create: `packages/sample/lib/src/todos/todo.dart`
- Create: `packages/sample/lib/src/todos/todo_use_cases.dart`
- Create: `packages/sample/lib/src/todos/todo_controller.dart`
- Create: `packages/sample/test/todo_controller_test.dart`

- [ ] **Step 1: Write failing todo tests**

Create `packages/sample/test/todo_controller_test.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_sample/src/todos/todo.dart';
import 'package:blocpod_sample/src/todos/todo_controller.dart';
import 'package:blocpod_sample/src/todos/todo_use_cases.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load todo use case returns seed todos', () async {
    final result = await const LoadTodosUseCase().call(const NoTodoParams());

    expect(result, isA<Ok<List<Todo>>>());
  });

  test('todo controller adds valid todos', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(todoProvider.notifier).dispatch(const TodoLoaded());
    await container.read(todoProvider.notifier).dispatch(const TodoAdded('Write sample'));

    expect(
      container.read(todoProvider),
      isA<AsyncData<List<Todo>>>().having((value) => value.value.any((todo) => todo.title == 'Write sample'), 'has todo', true),
    );
  });

  test('todo controller exposes Result.error as AsyncError', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(todoProvider.notifier).dispatch(const TodoAdded(''));

    expect(container.read(todoProvider), isA<AsyncError<List<Todo>>>());
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```sh
(cd packages/sample && flutter test test/todo_controller_test.dart)
```

Expected: FAIL because todo files do not exist.

- [ ] **Step 3: Implement the todo model**

Create `packages/sample/lib/src/todos/todo.dart`:

```dart
final class Todo {
  const Todo({required this.id, required this.title, this.isDone = false});

  final int id;
  final String title;
  final bool isDone;

  Todo copyWith({String? title, bool? isDone}) {
    return Todo(id: id, title: title ?? this.title, isDone: isDone ?? this.isDone);
  }
}
```

- [ ] **Step 4: Implement use cases**

Create `packages/sample/lib/src/todos/todo_use_cases.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';

import 'todo.dart';

final class NoTodoParams {
  const NoTodoParams();
}

final class AddTodoParams {
  const AddTodoParams({required this.current, required this.title});

  final List<Todo> current;
  final String title;
}

final class LoadTodosUseCase extends UseCase<List<Todo>, NoTodoParams> {
  const LoadTodosUseCase();

  @override
  Future<Result<List<Todo>>> call(NoTodoParams params) async {
    return const Result.ok(<Todo>[
      Todo(id: 1, title: 'Read Blocpod architecture'),
      Todo(id: 2, title: 'Dispatch an event'),
    ]);
  }
}

final class AddTodoUseCase extends UseCase<List<Todo>, AddTodoParams> {
  const AddTodoUseCase();

  @override
  Future<Result<List<Todo>>> call(AddTodoParams params) async {
    final title = params.title.trim();
    if (title.isEmpty) {
      return Result.error(Exception('Todo title cannot be empty'));
    }

    final nextId = params.current.isEmpty ? 1 : params.current.map((todo) => todo.id).reduce((a, b) => a > b ? a : b) + 1;
    return Result.ok(<Todo>[...params.current, Todo(id: nextId, title: title)]);
  }
}
```

- [ ] **Step 5: Implement the todo controller**

Create `packages/sample/lib/src/todos/todo_controller.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'todo.dart';
import 'todo_use_cases.dart';

sealed class TodoEvent {
  const TodoEvent();
}

final class TodoLoaded extends TodoEvent {
  const TodoLoaded();
}

final class TodoAdded extends TodoEvent {
  const TodoAdded(this.title);

  final String title;
}

final todoProvider = AsyncNotifierProvider<TodoController, List<Todo>>(TodoController.new);

final class TodoController extends EventControllerNotifier<List<Todo>, TodoEvent> {
  final LoadTodosUseCase _loadTodos = const LoadTodosUseCase();
  final AddTodoUseCase _addTodo = const AddTodoUseCase();

  @override
  Future<List<Todo>> build() async => const <Todo>[];

  @override
  Future<void> onEvent(TodoEvent event) async {
    switch (event) {
      case TodoLoaded():
        await _apply(await _loadTodos.call(const NoTodoParams()));
      case TodoAdded(:final title):
        await _apply(await _addTodo.call(AddTodoParams(current: _currentTodos, title: title)));
    }
  }

  @override
  Map<String, Object?> metadataFor(TodoEvent event) {
    return switch (event) {
      TodoLoaded() => const {'action': 'load'},
      TodoAdded(:final title) => {'action': 'add', 'titleLength': title.length},
    };
  }

  @override
  String? stateLabel(AsyncValue<List<Todo>> state) {
    return switch (state) {
      AsyncData(:final value) => 'todos:${value.length}',
      AsyncLoading<List<Todo>>() => 'loading',
      AsyncError<List<Todo>>() => 'error',
    };
  }

  Future<void> _apply(Result<List<Todo>> result) async {
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
      case Error(:final error):
        state = AsyncError(error, StackTrace.current);
    }
  }

  List<Todo> get _currentTodos {
    return switch (state) {
      AsyncData(:final value) => value,
      _ => const <Todo>[],
    };
  }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:

```sh
(cd packages/sample && flutter test test/todo_controller_test.dart)
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```sh
git add packages/sample/lib/src/todos packages/sample/test/todo_controller_test.dart
git commit -m "feat: demonstrate blocpod use cases and results"
```

---

### Task 4: Add Provider Variant Dispatch Samples

**Files:**
- Create: `packages/sample/lib/src/provider_variants/provider_variants.dart`
- Create: `packages/sample/test/provider_variants_test.dart`

- [ ] **Step 1: Write failing provider variant tests**

Create `packages/sample/test/provider_variants_test.dart`:

```dart
import 'package:blocpod_sample/src/provider_variants/provider_variants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dispatch supports regular autoDispose family and autoDispose.family providers', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(regularVariantDispatchProvider);
    await container.read(autoDisposeVariantDispatchProvider);
    await container.read(familyVariantDispatchProvider(10));
    await container.read(autoDisposeFamilyVariantDispatchProvider(20));

    expect(container.read(regularVariantProvider), isA<AsyncData<int>>().having((value) => value.value, 'regular', 1));
    expect(container.read(autoDisposeVariantProvider), isA<AsyncData<int>>().having((value) => value.value, 'autoDispose', 1));
    expect(container.read(familyVariantProvider(10)), isA<AsyncData<int>>().having((value) => value.value, 'family', 11));
    expect(container.read(autoDisposeFamilyVariantProvider(20)), isA<AsyncData<int>>().having((value) => value.value, 'autoDisposeFamily', 21));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```sh
(cd packages/sample && flutter test test/provider_variants_test.dart)
```

Expected: FAIL because provider variant files do not exist.

- [ ] **Step 3: Implement provider variants**

Create `packages/sample/lib/src/provider_variants/provider_variants.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class VariantIncremented {
  const VariantIncremented();
}

final regularVariantProvider = AsyncNotifierProvider<VariantCounterController, int>(VariantCounterController.new);
final autoDisposeVariantProvider = AsyncNotifierProvider.autoDispose<VariantCounterController, int>(
  VariantCounterController.new,
);
final familyVariantProvider = AsyncNotifierProvider.family<FamilyVariantCounterController, int, int>(
  FamilyVariantCounterController.new,
);
final autoDisposeFamilyVariantProvider = AsyncNotifierProvider.autoDispose.family<FamilyVariantCounterController, int, int>(
  FamilyVariantCounterController.new,
);

final regularVariantDispatchProvider = Provider<Future<void>>((ref) {
  return ref.dispatch(regularVariantProvider, const VariantIncremented());
});
final autoDisposeVariantDispatchProvider = Provider<Future<void>>((ref) {
  return ref.dispatch(autoDisposeVariantProvider, const VariantIncremented());
});
final familyVariantDispatchProvider = Provider.family<Future<void>, int>((ref, initialValue) {
  return ref.dispatch(familyVariantProvider(initialValue), const VariantIncremented());
});
final autoDisposeFamilyVariantDispatchProvider = Provider.family<Future<void>, int>((ref, initialValue) {
  return ref.dispatch(autoDisposeFamilyVariantProvider(initialValue), const VariantIncremented());
});

final class VariantCounterController extends EventControllerNotifier<int, VariantIncremented> {
  @override
  Future<int> build() async => 0;

  @override
  Future<void> onEvent(VariantIncremented event) async {
    state = AsyncData(_currentValue + 1);
  }

  int get _currentValue => switch (state) {
    AsyncData(:final value) => value,
    _ => 0,
  };
}

final class FamilyVariantCounterController extends EventControllerNotifier<int, VariantIncremented> {
  FamilyVariantCounterController(this.initialValue);

  final int initialValue;

  @override
  Future<int> build() async => initialValue;

  @override
  Future<void> onEvent(VariantIncremented event) async {
    state = AsyncData(_currentValue + 1);
  }

  int get _currentValue => switch (state) {
    AsyncData(:final value) => value,
    _ => initialValue,
  };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```sh
(cd packages/sample && flutter test test/provider_variants_test.dart)
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```sh
git add packages/sample/lib/src/provider_variants/provider_variants.dart packages/sample/test/provider_variants_test.dart
git commit -m "feat: demonstrate blocpod provider variants"
```

---

### Task 5: Add Logging Sink And App UI

**Files:**
- Create: `packages/sample/lib/main.dart`
- Create: `packages/sample/lib/src/app.dart`
- Create: `packages/sample/lib/src/counter/counter_panel.dart`
- Create: `packages/sample/lib/src/todos/todo_panel.dart`
- Create: `packages/sample/lib/src/provider_variants/provider_variants_panel.dart`
- Create: `packages/sample/lib/src/logging/in_memory_log_sink.dart`
- Create: `packages/sample/lib/src/logging/log_panel.dart`
- Create: `packages/sample/test/logging_test.dart`

- [ ] **Step 1: Write failing logging test**

Create `packages/sample/test/logging_test.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:blocpod_sample/src/counter/counter_controller.dart';
import 'package:blocpod_sample/src/logging/in_memory_log_sink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sample log sink stores formatted Blocpod log entries', () async {
    final sink = InMemoryLogSink();
    final container = ProviderContainer(
      overrides: [eventLoggerProvider.overrideWithValue(BlocpodEventLogger(sink))],
    );
    addTearDown(container.dispose);

    await container.read(counterProvider.notifier).dispatch(const CounterIncremented(1));

    expect(sink.entries, isNotEmpty);
    expect(sink.entries.map((entry) => entry.message), contains(contains('eventCompleted')));
    expect(sink.entries.map((entry) => entry.level), everyElement(BlocpodLogLevel.info));
    expect(sink.entries.last.metadata, containsPair('controllerName', 'SampleCounterController'));
  });
}
```

- [ ] **Step 2: Run logging test to verify it fails**

Run:

```sh
(cd packages/sample && flutter test test/logging_test.dart)
```

Expected: FAIL because `InMemoryLogSink` does not exist.

- [ ] **Step 3: Implement the in-memory sink**

Create `packages/sample/lib/src/logging/in_memory_log_sink.dart`:

```dart
import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final inMemoryLogSinkProvider = ChangeNotifierProvider<InMemoryLogSink>((ref) {
  return InMemoryLogSink();
});

final class InMemoryLogSink extends ChangeNotifier implements BlocpodLogSink {
  final List<BlocpodLogEntry> _entries = <BlocpodLogEntry>[];

  List<BlocpodLogEntry> get entries => List<BlocpodLogEntry>.unmodifiable(_entries);

  @override
  void write(BlocpodLogEntry entry) {
    _entries.add(entry);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
```

- [ ] **Step 4: Implement `main.dart` with logger override**

Create `packages/sample/lib/main.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_arch_logger/blocpod_arch_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/logging/in_memory_log_sink.dart';

void main() {
  final sink = InMemoryLogSink();

  runApp(
    ProviderScope(
      overrides: [
        inMemoryLogSinkProvider.overrideWithValue(sink),
        eventLoggerProvider.overrideWithValue(BlocpodEventLogger(sink)),
      ],
      child: const BlocpodSampleApp(),
    ),
  );
}
```

- [ ] **Step 5: Implement the UI files**

Create `packages/sample/lib/src/app.dart`:

```dart
// packages/sample/lib/src/app.dart
import 'package:flutter/material.dart';

import 'counter/counter_panel.dart';
import 'logging/log_panel.dart';
import 'provider_variants/provider_variants_panel.dart';
import 'todos/todo_panel.dart';

final class BlocpodSampleApp extends StatelessWidget {
  const BlocpodSampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blocpod Sample',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const SampleHomeScreen(),
    );
  }
}

final class SampleHomeScreen extends StatelessWidget {
  const SampleHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppBar(title: Text('Blocpod Sample')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CounterPanel(),
            SizedBox(height: 16),
            TodoPanel(),
            SizedBox(height: 16),
            ProviderVariantsPanel(),
            SizedBox(height: 16),
            LogPanel(),
          ],
        ),
      ),
    );
  }
}
```

Create `packages/sample/lib/src/counter/counter_panel.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'counter_controller.dart';

final class CounterPanel extends ConsumerWidget {
  const CounterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counter = ref.watch(counterProvider);

    return _SampleSection(
      title: 'Counter events',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (counter) {
            AsyncData(:final value) => 'Count: $value',
            AsyncLoading<int>() => 'Loading...',
            AsyncError<int>() => 'Counter error',
          }),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: () => ref.dispatch(counterProvider, const CounterIncremented(1)), child: const Text('+1')),
              OutlinedButton(onPressed: () => ref.dispatch(counterProvider, const CounterDecremented()), child: const Text('-1')),
              OutlinedButton(onPressed: () => ref.dispatch(counterProvider, const CounterReset()), child: const Text('Reset')),
              OutlinedButton(
                onPressed: () => ref.dispatch(counterProvider, const CounterResetThroughChild()),
                child: const Text('Nested reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _SampleSection extends StatelessWidget {
  const _SampleSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8), child]),
      ),
    );
  }
}
```

Create `packages/sample/lib/src/todos/todo_panel.dart`:

```dart
import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'todo_controller.dart';

final class TodoPanel extends ConsumerStatefulWidget {
  const TodoPanel({super.key});

  @override
  ConsumerState<TodoPanel> createState() => _TodoPanelState();
}

final class _TodoPanelState extends ConsumerState<TodoPanel> {
  final TextEditingController _controller = TextEditingController(text: 'Try Blocpod');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(todoProvider);

    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UseCase and Result', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Todo title')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: () => ref.dispatch(todoProvider, const TodoLoaded()), child: const Text('Load')),
                FilledButton(onPressed: () => ref.dispatch(todoProvider, TodoAdded(_controller.text)), child: const Text('Add')),
                OutlinedButton(onPressed: () => ref.dispatch(todoProvider, const TodoAdded('')), child: const Text('Fail')),
              ],
            ),
            const SizedBox(height: 8),
            switch (todos) {
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final todo in value) Text('- ${todo.title}')],
              ),
              AsyncLoading() => const Text('Loading...'),
              AsyncError(:final error) => Text('Error: $error'),
            },
          ],
        ),
      ),
    );
  }
}
```

Create `packages/sample/lib/src/provider_variants/provider_variants_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'provider_variants.dart';

final class ProviderVariantsPanel extends ConsumerWidget {
  const ProviderVariantsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regular = ref.watch(regularVariantProvider);
    final autoDispose = ref.watch(autoDisposeVariantProvider);
    final family = ref.watch(familyVariantProvider(10));
    final autoDisposeFamily = ref.watch(autoDisposeFamilyVariantProvider(20));

    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Provider variants', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('regular=${_label(regular)} autoDispose=${_label(autoDispose)} family=${_label(family)} autoDispose.family=${_label(autoDisposeFamily)}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(onPressed: () => ref.read(regularVariantDispatchProvider), child: const Text('Regular')),
                FilledButton(onPressed: () => ref.read(autoDisposeVariantDispatchProvider), child: const Text('Auto')),
                FilledButton(onPressed: () => ref.read(familyVariantDispatchProvider(10)), child: const Text('Family')),
                FilledButton(onPressed: () => ref.read(autoDisposeFamilyVariantDispatchProvider(20)), child: const Text('Auto family')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _label(AsyncValue<int> value) {
    return switch (value) {
      AsyncData(:final value) => '$value',
      AsyncLoading<int>() => 'loading',
      AsyncError<int>() => 'error',
    };
  }
}
```

Create `packages/sample/lib/src/logging/log_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'in_memory_log_sink.dart';

final class LogPanel extends ConsumerWidget {
  const LogPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sink = ref.watch(inMemoryLogSinkProvider);
    final entries = sink.entries.reversed.take(20).toList(growable: false);

    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Event log', style: Theme.of(context).textTheme.titleMedium)),
                TextButton(onPressed: sink.clear, child: const Text('Clear')),
              ],
            ),
            const SizedBox(height: 8),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${entry.message}\n${_metadataSummary(entry.metadata)}'),
              ),
          ],
        ),
      ),
    );
  }

  String _metadataSummary(Map<String, Object?> metadata) {
    final keys = ['phase', 'eventName', 'traceId', 'spanId', 'parentSpanId', 'transitionIndex', 'hasChanged'];
    return keys.where(metadata.containsKey).map((key) => '$key=${metadata[key]}').join(' ');
  }
}
```

If these exact snippets become visually cramped during implementation, keep the same controls and behavior but split shared section styling into a small helper widget.

- [ ] **Step 6: Run logging and widget smoke tests**

Run:

```sh
(cd packages/sample && flutter test test/logging_test.dart)
```

Expected: PASS.

- [ ] **Step 7: Manually run the app**

Run:

```sh
(cd packages/sample && flutter run -d chrome)
```

Expected: app starts without extra setup. The first screen shows counter, todo, provider variants, and event log panels. Pressing each panel button changes visible state and appends at least one corresponding log entry.

- [ ] **Step 8: Commit**

Run:

```sh
git add packages/sample/lib packages/sample/test/logging_test.dart
git commit -m "feat: add interactive blocpod sample app"
```

---

### Task 6: Update Workspace Documentation

**Files:**
- Modify: `README.md`
- Modify: `packages/sample/README.md`

- [ ] **Step 1: Add sample documentation to root README**

Modify `README.md` package list:

```markdown
- `packages/sample` (`blocpod_sample`): private Flutter sample app demonstrating all Blocpod packages together.
```

Add local commands:

```sh
(cd packages/sample && flutter test)
(cd packages/sample && flutter run)
```

Add feature map:

```markdown
## Sample Feature Map

- Event controller and dispatch: `packages/sample/lib/src/counter/counter_controller.dart`
- Widget dispatch: `packages/sample/lib/src/counter/counter_panel.dart`
- Result and UseCase: `packages/sample/lib/src/todos/todo_use_cases.dart`
- Provider variants: `packages/sample/lib/src/provider_variants/provider_variants.dart`
- Logger bridge and sink: `packages/sample/lib/src/logging/in_memory_log_sink.dart`
- Trace and transition output: `packages/sample/lib/src/logging/log_panel.dart`
```

- [ ] **Step 2: Expand sample README**

Modify `packages/sample/README.md` with the same feature map and the expected UI workflow:

```markdown
1. Press counter buttons to emit dispatch, transition, and completion records.
2. Press nested reset to see parent and child spans sharing one trace id.
3. Add a todo to see `Result.ok`.
4. Add an empty todo to see `Result.error` become `AsyncError`.
5. Dispatch provider variants to see regular, `autoDispose`, `family`, and `autoDispose.family` support.
```

Also add a panel-to-file map:

```markdown
## Panel To Source Map

- Counter events panel: `lib/src/counter/counter_panel.dart` and `lib/src/counter/counter_controller.dart`
- UseCase and Result panel: `lib/src/todos/todo_panel.dart`, `lib/src/todos/todo_controller.dart`, and `lib/src/todos/todo_use_cases.dart`
- Provider variants panel: `lib/src/provider_variants/provider_variants_panel.dart` and `lib/src/provider_variants/provider_variants.dart`
- Event log panel: `lib/src/logging/log_panel.dart` and `lib/src/logging/in_memory_log_sink.dart`
```

- [ ] **Step 3: Run docs-adjacent verification**

Run:

```sh
git diff --check README.md packages/sample/README.md
```

Expected: no whitespace errors.

- [ ] **Step 4: Commit**

Run:

```sh
git add README.md packages/sample/README.md
git commit -m "docs: document blocpod sample app"
```

---

### Task 7: Final Verification

**Files:**
- Verify all files changed in prior tasks.

- [ ] **Step 1: Format**

Run:

```sh
dart format --line-length 120 .
```

Expected: formatter completes with no syntax errors.

- [ ] **Step 2: Analyze**

Run:

```sh
flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Run package tests**

Run:

```sh
(cd packages/arch && flutter test)
(cd packages/logger && flutter test)
(cd packages/arch_logger && flutter test)
(cd packages/sample && flutter test)
```

Expected: all tests pass.

- [ ] **Step 4: Confirm workspace**

Run:

```sh
dart pub workspace list
```

Expected: includes `blocpod_arch`, `blocpod_logger`, `blocpod_arch_logger`, and `blocpod_sample`.

- [ ] **Step 5: Verify the runnable sample app**

Run:

```sh
(cd packages/sample && flutter run -d chrome)
```

Expected: the app launches to the working sample screen. Counter, todo, provider variants, and log panels are visible without navigation. Buttons update their panel state and log output.

- [ ] **Step 6: Inspect git status**

Run:

```sh
git status -sb
```

Expected: clean if commits were made after every task.

---

## Execution Notes

- If `flutter_riverpod` `3.3.1` is stale relative to existing package lock resolution, use the version already accepted by the workspace resolver.
- If UI tests are added later, prefer shallow widget smoke tests. The controller tests carry the core behavior.
- Do not commit generated or runtime files outside the sample package and workspace lockfile changes.
