import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';

const Set<String> _reservedMetadataKeys = <String>{
  'phase',
  'traceId',
  'spanId',
  'parentSpanId',
  'controllerName',
  'eventName',
  'durationMicros',
  'transitionIndex',
  'previousStateKind',
  'nextStateKind',
  'hasChanged',
  'previousStateLabel',
  'nextStateLabel',
  'stateMetadata',
};

/// Converts Blocpod architecture event records into generic log entries.
final class EventLogRecordFormatter {
  const EventLogRecordFormatter();

  /// Formats [record].
  BlocpodLogEntry format(EventLogRecord record) {
    return BlocpodLogEntry(
      level: record.error == null ? BlocpodLogLevel.info : BlocpodLogLevel.error,
      message: _messageFor(record),
      timestamp: record.startedAt,
      metadata: <String, Object?>{
        for (final entry in record.metadata.entries)
          if (!_reservedMetadataKeys.contains(entry.key)) entry.key: entry.value,
        'phase': record.phase.name,
        'traceId': record.traceContext.traceId,
        'spanId': record.traceContext.spanId,
        if (record.traceContext.parentSpanId != null) 'parentSpanId': record.traceContext.parentSpanId,
        'controllerName': record.controllerName,
        if (record.eventName != null) 'eventName': record.eventName,
        if (record.duration != null) 'durationMicros': record.duration!.inMicroseconds,
        if (record.transitionIndex != null) 'transitionIndex': record.transitionIndex,
        if (record.previousStateKind != null) 'previousStateKind': record.previousStateKind!.name,
        if (record.nextStateKind != null) 'nextStateKind': record.nextStateKind!.name,
        if (record.hasChanged != null) 'hasChanged': record.hasChanged,
        if (record.previousStateLabel != null) 'previousStateLabel': record.previousStateLabel,
        if (record.nextStateLabel != null) 'nextStateLabel': record.nextStateLabel,
        if (record.stateMetadata.isNotEmpty) 'stateMetadata': record.stateMetadata,
      },
      error: record.error,
      stackTrace: record.stackTrace,
    );
  }

  String _messageFor(EventLogRecord record) {
    final eventName = record.eventName;
    final states = _statesFor(record);
    final duration = record.duration;
    final durationText = duration == null ? '' : ' ${duration.inMilliseconds}ms';

    return switch (record.phase) {
      EventLogPhase.controllerCreated => '${record.controllerName} controllerCreated',
      EventLogPhase.controllerDisposed => '${record.controllerName} controllerDisposed',
      EventLogPhase.eventStarted => '${record.controllerName} ${eventName ?? 'unknownEvent'} eventStarted$states',
      EventLogPhase.transition =>
        '${record.controllerName} ${eventName ?? 'unknownEvent'} transition#${record.transitionIndex ?? 0}$states',
      EventLogPhase.eventCompleted =>
        '${record.controllerName} ${eventName ?? 'unknownEvent'} eventCompleted$states$durationText',
      EventLogPhase.eventFailed =>
        '${record.controllerName} ${eventName ?? 'unknownEvent'} eventFailed$states$durationText',
    };
  }

  String _statesFor(EventLogRecord record) {
    final previous = record.previousStateKind?.name;
    final next = record.nextStateKind?.name;

    if (previous == null && next == null) {
      return '';
    }
    if (next == null) {
      return ' $previous';
    }
    if (previous == null) {
      return ' ->$next';
    }

    return ' $previous->$next';
  }
}
