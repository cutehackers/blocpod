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
