import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _forbiddenExternalLoggerPackages = <String>['talker', 'logging', 'sentry', 'firebase_crashlytics'];

List<String> _findForbiddenExternalLoggerReferences(String path, String source) {
  final offenders = <String>[];
  for (final package in _forbiddenExternalLoggerPackages) {
    final import = 'package:$package/';
    if (source.contains(import)) {
      offenders.add('$path: $import');
    }
  }

  if (path.endsWith('pubspec.yaml')) {
    for (final package in _findForbiddenYamlDependencyKeys(source)) {
      offenders.add('$path: $package');
    }
  }

  return offenders;
}

Iterable<String> _findForbiddenYamlDependencyKeys(String source) sync* {
  final sectionHeader = RegExp(r'^([ \t]*)(?:dependencies|dev_dependencies|dependency_overrides)\s*:\s*(?:#.*)?$');
  final dependencyKey = RegExp(r'^[ \t]*([A-Za-z0-9_-]+)\s*:');
  var sectionIndentation = -1;

  for (final line in source.split('\n')) {
    final header = sectionHeader.firstMatch(line);
    if (header != null) {
      sectionIndentation = header.group(1)!.length;
      continue;
    }

    if (sectionIndentation < 0) {
      continue;
    }

    final trimmed = line.trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }

    final indentation = line.length - trimmed.length;
    if (indentation <= sectionIndentation) {
      sectionIndentation = -1;
      continue;
    }

    final key = dependencyKey.firstMatch(line)?.group(1);
    if (key != null && _forbiddenExternalLoggerPackages.contains(key)) {
      yield key;
    }
  }
}

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

  test('blocpod_logger has no external logger SDK dependency', () {
    final files = <File>[
      File('pubspec.yaml'),
      ...Directory('lib').listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart')),
    ];

    final offenders = <String>[];
    for (final file in files) {
      offenders.addAll(_findForbiddenExternalLoggerReferences(file.path, file.readAsStringSync()));
    }

    expect(offenders, isEmpty);
  });

  test('external logger guard detects YAML dependency keys and package imports', () {
    const pubspecFixture = '''
description: 'Documentation can mention talker: ^4.0.0 safely.'
dependencies:
  talker: ^4.0.0
  logging:
    path: ../logging
  sentry: ^8.0.0
  firebase_crashlytics: ^4.0.0
''';
    const sourceFixture = "import 'package:logging/logging.dart';";

    expect(_findForbiddenExternalLoggerReferences('pubspec.yaml', pubspecFixture), <String>[
      'pubspec.yaml: talker',
      'pubspec.yaml: logging',
      'pubspec.yaml: sentry',
      'pubspec.yaml: firebase_crashlytics',
    ]);
    expect(_findForbiddenExternalLoggerReferences('lib/adapter.dart', sourceFixture), <String>[
      'lib/adapter.dart: package:logging/',
    ]);
  });
}
