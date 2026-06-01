import 'blocpod_log_entry.dart';

/// Output sink for Blocpod log entries.
abstract interface class BlocpodLogSink {
  /// Writes [entry].
  void write(BlocpodLogEntry entry);
}
