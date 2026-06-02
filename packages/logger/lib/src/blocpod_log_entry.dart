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
