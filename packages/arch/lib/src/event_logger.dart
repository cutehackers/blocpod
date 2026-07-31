import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_log_record.dart';

/// Synchronous sink for structured event dispatch records.
///
/// Blocpod delivers framework records through one Dart-isolate-wide,
/// non-reentrant FIFO gate. A record emitted by a logger callback is delivered
/// only after that callback returns, in occurrence and [EventLogRecord.recordSequence]
/// order. Each callback runs without an ambient event dispatch or trace
/// context, so work started by a logger is independent of the observed event.
///
/// Logger failures are isolated per record and never change controller state,
/// dispatch results, handler errors, provider lifecycle, or disposal. Because
/// delivery is synchronous, a slow implementation delays the framework
/// operation that emitted the record. Adapters that need asynchronous output
/// must provide their own buffering while keeping [log] synchronous.
abstract interface class EventLogger {
  /// Receives one immutable observation record.
  void log(EventLogRecord record);
}

/// Default logger that intentionally drops records.
final class NoopEventLogger implements EventLogger {
  const NoopEventLogger();

  @override
  void log(EventLogRecord record) {}
}

/// Current event logger for arch controllers.
final eventLoggerProvider = Provider<EventLogger>((ref) {
  return const NoopEventLogger();
});
