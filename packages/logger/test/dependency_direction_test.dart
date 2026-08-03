import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocpod_logger does not import blocpod_arch', () {
    const forbiddenImport =
        'package:blocpod_'
        'arch/';
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final offenders = <String>[];
    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      if (source.contains(forbiddenImport)) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty);
  });

  test('blocpod_logger has no external logger SDK dependency', () {
    const forbiddenExternalLoggers = <String>[
      'package:talker/',
      'package:logging/',
      'package:sentry/',
      'package:firebase_crashlytics/',
    ];
    final files = <File>[
      File('pubspec.yaml'),
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];

    final offenders = <String>[];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final dependency in forbiddenExternalLoggers) {
        if (source.contains(dependency)) {
          offenders.add('${file.path}: $dependency');
        }
      }
    }

    expect(offenders, isEmpty);
  });
}
