import 'package:flutter/foundation.dart';

import 'blocpod_log_entry.dart';
import 'json_log_encoder.dart';
import 'blocpod_log_encoder.dart';
import 'blocpod_log_sink.dart';

/// Log sink that writes formatted entries through Flutter's [debugPrint].
final class DebugPrintLogSink implements BlocpodLogSink {
  DebugPrintLogSink({
    BlocpodLogEncoder encoder = const JsonLogEncoder(),
    DebugPrintCallback? debugPrintOverride,
  })  : _encoder = encoder,
        _debugPrint = debugPrintOverride ?? debugPrint;

  final BlocpodLogEncoder _encoder;
  final DebugPrintCallback _debugPrint;

  @override
  void write(BlocpodLogEntry entry) {
    _debugPrint(_encoder.encode(entry));
  }
}

/// Formats [entry] as JSON Lines for local development logs.
String formatBlocpodLogEntry(BlocpodLogEntry entry) {
  return const JsonLogEncoder().encode(entry);
}
