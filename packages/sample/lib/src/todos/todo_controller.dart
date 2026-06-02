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
