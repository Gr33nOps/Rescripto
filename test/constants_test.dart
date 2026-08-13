import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/core/constants.dart';

void main() {
  group('AppConstants.versionName', () {
    test('stays in step with the `version:` line in pubspec.yaml', () {
      // AppConstants.versionName is a hand-maintained copy of pubspec.yaml's
      // version (shown in Settings > About, and stamped into every backup
      // bundle's app_version field) because nothing reads pubspec.yaml at
      // runtime. A version-bump commit that only edits pubspec.yaml — which
      // is exactly what happened for the 1.1.1 release — leaves this
      // constant, and everything that displays it, silently wrong. This
      // test is the one thing that would have caught that.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*(\d+\.\d+\.\d+)',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'pubspec.yaml has no `version:` line');

      expect(AppConstants.versionName, match!.group(1));
    });
  });
}
