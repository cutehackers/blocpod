import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'event_log_record.dart';

/// Sink for structured event dispatch records.
abstract interface class EventLogger {
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
