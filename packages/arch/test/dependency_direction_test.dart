import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocpod_arch never imports blocpod_logger', () {
    final libDirectory = Directory('lib');

    final dartFiles = libDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final contents = file.readAsStringSync();

      expect(
        contents,
        isNot(contains('package:blocpod_logger/')),
        reason: '${file.path} must not import package:blocpod_logger/',
      );
    }
  });
}
