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
