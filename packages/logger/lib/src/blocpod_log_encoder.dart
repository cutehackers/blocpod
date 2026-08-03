import 'blocpod_log_entry.dart';

/// Converts a structured Blocpod log entry to text for string-based sinks.
abstract interface class BlocpodLogEncoder {
  /// Encodes [entry] without changing it.
  String encode(BlocpodLogEntry entry);
}
