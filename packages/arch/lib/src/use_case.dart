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
