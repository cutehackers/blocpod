import 'dart:collection';

import 'event_dispatch_context.dart';
import 'event_log_record.dart';
import 'event_logger.dart';

final class ObservationRuntime {
  static int _lastRecordSequence = 0;
  static final Queue<_DeliverySlot> _deliverySlots = Queue();
  static bool _isDraining = false;

  static ObservationOccurrence capture() {
    final slot = _DeliverySlot();
    _deliverySlots.addLast(slot);
    return ObservationOccurrence._(
      occurredAt: DateTime.now().toUtc(),
      recordSequence: ++_lastRecordSequence,
      slot: slot,
    );
  }

  static void publish(ObservationOccurrence occurrence, EventLogger? logger, EventLogRecord record) {
    if (logger == null) {
      cancel(occurrence);
      return;
    }

    occurrence._slot.commit(_PendingDelivery(logger, record));
    _drain();
  }

  static void cancel(ObservationOccurrence occurrence) {
    occurrence._slot.cancel();
    _drain();
  }

  static void _drain() {
    if (_isDraining) {
      return;
    }

    _isDraining = true;
    try {
      while (_deliverySlots.isNotEmpty) {
        final slot = _deliverySlots.first;
        if (slot.state == _DeliverySlotState.pending) {
          return;
        }

        _deliverySlots.removeFirst();
        if (slot.state == _DeliverySlotState.canceled) {
          continue;
        }

        final delivery = slot.delivery!;
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
  ObservationOccurrence._({required this.occurredAt, required this.recordSequence, required this._slot});

  final DateTime occurredAt;
  final int recordSequence;
  final _DeliverySlot _slot;
}

final class _PendingDelivery {
  const _PendingDelivery(this.logger, this.record);

  final EventLogger logger;
  final EventLogRecord record;
}

enum _DeliverySlotState { pending, committed, canceled }

final class _DeliverySlot {
  _DeliverySlotState state = _DeliverySlotState.pending;
  _PendingDelivery? delivery;

  void commit(_PendingDelivery next) {
    if (state != _DeliverySlotState.pending) {
      return;
    }
    delivery = next;
    state = _DeliverySlotState.committed;
  }

  void cancel() {
    if (state != _DeliverySlotState.pending) {
      return;
    }
    state = _DeliverySlotState.canceled;
  }
}
