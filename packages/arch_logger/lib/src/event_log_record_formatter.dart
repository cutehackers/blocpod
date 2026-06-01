import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';

const Set<String> _reservedMetadataKeys = <String>{
  'traceId',
  'spanId',
  'parentSpanId',
  'controllerName',
  'eventName',
  'durationMicros',
  'beforeStateKind',
  'afterStateKind',
  'hasChanged',
};

/// Converts Blocpod architecture event records into generic log entries.
final class EventLogRecordFormatter {
  const EventLogRecordFormatter();

  /// Formats [record].
  BlocpodLogEntry format(EventLogRecord record) {
    final beforeKind = record.beforeStateKind.name;
    final afterKind = record.afterStateKind.name;

    return BlocpodLogEntry(
      level: record.error == null
          ? BlocpodLogLevel.info
          : BlocpodLogLevel.error,
      message:
          '${record.controllerName} ${record.eventName} $beforeKind->$afterKind ${record.duration.inMilliseconds}ms',
      timestamp: record.startedAt,
      metadata: <String, Object?>{
        for (final entry in record.metadata.entries)
          if (!_reservedMetadataKeys.contains(entry.key))
            entry.key: entry.value,
        'traceId': record.traceContext.traceId,
        'spanId': record.traceContext.spanId,
        if (record.traceContext.parentSpanId != null)
          'parentSpanId': record.traceContext.parentSpanId,
        'controllerName': record.controllerName,
        'eventName': record.eventName,
        'durationMicros': record.duration.inMicroseconds,
        'beforeStateKind': beforeKind,
        'afterStateKind': afterKind,
        'hasChanged': record.hasChanged,
      },
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }
}
