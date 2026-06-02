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
      isA<AsyncData<List<Todo>>>().having(
        (value) => value.value.any((todo) => todo.title == 'Write sample'),
        'has todo',
        true,
      ),
    );
  });

  test('todo controller exposes Result.error as AsyncError', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(todoProvider.notifier).dispatch(const TodoAdded(''));

    expect(container.read(todoProvider), isA<AsyncError<List<Todo>>>());
  });
}
