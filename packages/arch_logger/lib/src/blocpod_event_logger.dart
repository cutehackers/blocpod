import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';

import 'event_log_record_formatter.dart';

/// [EventLogger] implementation backed by a [BlocpodLogSink].
final class BlocpodEventLogger implements EventLogger {
  const BlocpodEventLogger(this.sink, {this.formatter = const EventLogRecordFormatter()});

  /// Target log sink.
  final BlocpodLogSink sink;

  /// Record formatter.
  final EventLogRecordFormatter formatter;

  @override
  void log(EventLogRecord record) {
    try {
      sink.write(formatter.format(record));
    } catch (_) {
      // Sink failures must not break application flow.
    }
  }
}
