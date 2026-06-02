import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocpod_logger does not import blocpod_arch', () {
    const forbiddenImport =
        'package:blocpod_'
        'arch/';
    final dartFiles = Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      if (source.contains(forbiddenImport)) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
