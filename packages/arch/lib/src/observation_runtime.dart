import 'dart:collection';

import 'event_dispatch_context.dart';
import 'event_log_record.dart';
import 'event_logger.dart';

final class ObservationRuntime {
  static int _lastRecordSequence = 0;
  static final Queue<_PendingDelivery> _pendingDeliveries = Queue();
  static bool _isDraining = false;

  static ObservationOccurrence capture() {
    return ObservationOccurrence._(
      occurredAt: DateTime.now().toUtc(),
      recordSequence: ++_lastRecordSequence,
    );
  }

  static void emit(EventLogger? logger, EventLogRecord record) {
    if (logger == null) {
      return;
    }

    _pendingDeliveries.addLast(_PendingDelivery(logger, record));
    if (_isDraining) {
      return;
    }

    _isDraining = true;
    try {
      while (_pendingDeliveries.isNotEmpty) {
        final delivery = _pendingDeliveries.removeFirst();
        EventDispatchContext.runWithoutContext(() {
          try {
            delivery.logger.log(delivery.record);
          } catch (_) {
            // Logger failures must not affect application flow or delivery.
          }
        });
      }
    } finally {
      _isDraining = false;
    }
  }
}

final class ObservationOccurrence {
  ObservationOccurrence._({
    required this.occurredAt,
    required this.recordSequence,
  });

  final DateTime occurredAt;
  final int recordSequence;
}

final class _PendingDelivery {
  const _PendingDelivery(this.logger, this.record);

  final EventLogger logger;
  final EventLogRecord record;
}
