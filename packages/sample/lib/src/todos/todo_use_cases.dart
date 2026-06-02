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

    final nextId = params.current.isEmpty
        ? 1
        : params.current.map((todo) => todo.id).reduce((a, b) => a > b ? a : b) + 1;
    return Result.ok(<Todo>[...params.current, Todo(id: nextId, title: title)]);
  }
}
