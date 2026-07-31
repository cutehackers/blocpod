final class ObservationOccurrence {
  ObservationOccurrence._({required this.occurredAt, required this.recordSequence});

  static int _lastRecordSequence = 0;

  final DateTime occurredAt;
  final int recordSequence;

  static ObservationOccurrence capture() {
    return ObservationOccurrence._(occurredAt: DateTime.now().toUtc(), recordSequence: ++_lastRecordSequence);
  }
}
