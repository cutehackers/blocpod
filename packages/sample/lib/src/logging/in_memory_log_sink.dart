import 'package:blocpod_logger/blocpod_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final inMemoryLogSinkProvider = Provider<InMemoryLogSink>((ref) {
  return InMemoryLogSink();
});

final class InMemoryLogSink extends ChangeNotifier implements BlocpodLogSink {
  final List<BlocpodLogEntry> _entries = <BlocpodLogEntry>[];

  List<BlocpodLogEntry> get entries => List<BlocpodLogEntry>.unmodifiable(_entries);

  @override
  void write(BlocpodLogEntry entry) {
    _entries.add(entry);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
