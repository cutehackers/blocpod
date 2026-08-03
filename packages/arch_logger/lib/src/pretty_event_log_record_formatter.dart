import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';

import 'event_log_record_formatter.dart';

/// Formats Blocpod records for local, human-readable transition debugging.
final class PrettyEventLogRecordFormatter implements BlocpodEventLogFormatter {
  const PrettyEventLogRecordFormatter();

  @override
  BlocpodLogEntry format(EventLogRecord record) {
    final compact = const EventLogRecordFormatter().format(record);
    return BlocpodLogEntry(
      level: compact.level,
      message: _messageFor(record),
      timestamp: compact.timestamp,
      sequence: compact.sequence,
      traceId: compact.traceId,
      spanId: compact.spanId,
      parentSpanId: compact.parentSpanId,
      attributes: compact.attributes,
      error: compact.error,
      stackTrace: compact.stackTrace,
    );
  }

  String _messageFor(EventLogRecord record) {
    return switch (record.phase) {
      EventLogPhase.controllerCreated => '🟢 ${record.controllerName} created',
      EventLogPhase.initialStateEstablished =>
        '🔵 ${record.controllerName} established ${_stateText(record.nextStateKind, record.nextStateLabel)}',
      EventLogPhase.controllerDisposed => '⚪ ${record.controllerName} disposed',
      EventLogPhase.eventStarted =>
        '🟡 ${record.controllerName} · ${record.eventName ?? 'unknownEvent'} started from ${_stateText(record.previousStateKind, record.previousStateLabel)}',
      EventLogPhase.transition =>
        '✨ ${record.controllerName} · ${record.eventName ?? 'unknownEvent'} transition[${record.transitionIndex ?? 0}] ${_stateChangeText(record)}',
      EventLogPhase.eventCompleted => _eventFinishedMessage('✅', 'completed', record),
      EventLogPhase.eventFailed => _eventFinishedMessage('🔴', 'failed', record),
    };
  }

  String _eventFinishedMessage(String emoji, String verb, EventLogRecord record) {
    final durationSuffix = record.duration == null ? '' : ' in ${_formatDuration(record.duration!)}';
    return '$emoji ${record.controllerName} · ${record.eventName ?? 'unknownEvent'} $verb ${_stateChangeText(record)}$durationSuffix';
  }

  String _stateText(AsyncValueKind? kind, String? label) {
    final kindText = kind?.name ?? 'unknown';
    if (label == null || label.isEmpty) {
      return kindText;
    }
    return '$kindText($label)';
  }

  String _stateChangeText(EventLogRecord record) {
    return '${_stateText(record.previousStateKind, record.previousStateLabel)} → ${_stateText(record.nextStateKind, record.nextStateLabel)}';
  }

  String _formatDuration(Duration duration) {
    final microseconds = duration.inMicroseconds;
    if (microseconds < Duration.microsecondsPerMillisecond) {
      return '${microseconds}µs';
    }
    if (microseconds < Duration.microsecondsPerSecond) {
      return '${microseconds ~/ Duration.microsecondsPerMillisecond}ms';
    }
    return '${(microseconds / Duration.microsecondsPerSecond).toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}s';
  }
}
