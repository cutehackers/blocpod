import 'blocpod_log_level.dart';

/// Generic structured log entry emitted by Blocpod log sinks.
final class BlocpodLogEntry {
  const BlocpodLogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.sequence,
    this.traceId,
    this.spanId,
    this.parentSpanId,
    this.attributes = const <String, Object?>{},
    this.error,
    this.stackTrace,
  });

  /// Entry severity.
  final BlocpodLogLevel level;

  /// Human-readable message.
  final String message;

  /// Entry timestamp.
  final DateTime timestamp;

  /// Monotonic sequence number when provided by the caller.
  final int? sequence;

  /// Distributed trace identifier when the entry is part of a trace.
  final String? traceId;

  /// Span identifier for this entry's current unit of work.
  final String? spanId;

  /// Parent span identifier when this entry belongs to a child span.
  final String? parentSpanId;

  /// Transport-neutral structured attributes for the entry.
  final Map<String, Object?> attributes;

  /// Associated error.
  final Object? error;

  /// Associated stack trace.
  final StackTrace? stackTrace;
}
