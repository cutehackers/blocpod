import 'package:blocpod_arch/blocpod_arch.dart';
import 'package:blocpod_logger/blocpod_logger.dart';

import 'event_log_record_formatter.dart';

const Set<String> _prettyReservedMetadataKeys = <String>{
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
      metadata: compact.metadata,
      error: compact.error,
      stackTrace: compact.stackTrace,
    );
  }

  String _messageFor(EventLogRecord record) {
    return switch (record.phase) {
      EventLogPhase.controllerCreated => _lifecycleMessage('🟢 controller.created', record),
      EventLogPhase.controllerDisposed => _lifecycleMessage('⚪ controller.disposed', record),
      EventLogPhase.eventStarted => _eventStartedMessage(record),
      EventLogPhase.transition => _transitionMessage(record),
      EventLogPhase.eventCompleted => _eventFinishedMessage('✅ event.completed', record),
      EventLogPhase.eventFailed => _eventFinishedMessage('🔴 event.failed', record),
    };
  }

  String _lifecycleMessage(String title, EventLogRecord record) {
    final buffer = StringBuffer()
      ..writeln('$title -- ${record.controllerName}')
      ..write('   trace: ${record.traceContext.traceId}/${record.traceContext.spanId}');
    _appendMetadataLine(buffer, 'metadata', record.metadata);
    return buffer.toString();
  }

  String _eventStartedMessage(EventLogRecord record) {
    final buffer = StringBuffer()
      ..writeln('🟡 event.started -- ${record.controllerName}, Event: ${record.eventName ?? 'unknownEvent'}')
      ..writeln('   previous: ${_stateText(record.previousStateKind, record.previousStateLabel)}')
      ..write('   trace: ${record.traceContext.traceId}/${record.traceContext.spanId}');
    _appendMetadataLine(buffer, 'eventMetadata', record.metadata);
    return buffer.toString();
  }

  String _transitionMessage(EventLogRecord record) {
    final buffer = StringBuffer()
      ..writeln('✨ state.transition -- ${record.controllerName}, Event: ${record.eventName ?? 'unknownEvent'}')
      ..writeln('   previous: ${_stateText(record.previousStateKind, record.previousStateLabel)}')
      ..writeln('   next: ${_stateText(record.nextStateKind, record.nextStateLabel)}')
      ..writeln('   transitionIndex: ${record.transitionIndex ?? 0}')
      ..write('   hasChanged: ${record.hasChanged ?? false}');
    _appendMetadataLine(buffer, 'eventMetadata', record.metadata);
    _appendMetadataLine(buffer, 'stateMetadata', record.stateMetadata);
    return buffer.toString();
  }

  String _eventFinishedMessage(String title, EventLogRecord record) {
    final durationText = record.duration == null ? 'unknown' : '${record.duration!.inMilliseconds}ms';
    final buffer = StringBuffer()
      ..writeln('$title -- ${record.controllerName}, Event: ${record.eventName ?? 'unknownEvent'}')
      ..writeln('   previous: ${_stateText(record.previousStateKind, record.previousStateLabel)}')
      ..writeln('   next: ${_stateText(record.nextStateKind, record.nextStateLabel)}')
      ..write('   duration: $durationText');
    _appendMetadataLine(buffer, 'eventMetadata', record.metadata);
    _appendMetadataLine(buffer, 'stateMetadata', record.stateMetadata);
    return buffer.toString();
  }

  String _stateText(AsyncValueKind? kind, String? label) {
    final kindText = kind?.name ?? 'unknown';
    if (label == null || label.isEmpty) {
      return kindText;
    }
    return '$kindText($label)';
  }

  void _appendMetadataLine(StringBuffer buffer, String label, Map<String, Object?> metadata) {
    final keys = _safeMetadataKeys(metadata);
    if (keys.isEmpty) {
      return;
    }
    buffer
      ..writeln()
      ..write('   ${label}Keys: ${keys.join(',')}');
  }

  List<String> _safeMetadataKeys(Map<String, Object?> metadata) {
    final keys = <String>[];
    for (final entry in metadata.entries) {
      if (_prettyReservedMetadataKeys.contains(entry.key) || _isSensitiveKey(entry.key)) {
        continue;
      }
      keys.add(entry.key);
    }
    return keys;
  }

  bool _isSensitiveKey(Object? key) {
    final normalized = key.toString().toLowerCase();
    return normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('credential') ||
        normalized.contains('password');
  }
}
