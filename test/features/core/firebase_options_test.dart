import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/firebase_options.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android e iOS usam o projeto Firebase do app', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(DefaultFirebaseOptions.currentPlatform,
        same(DefaultFirebaseOptions.android));

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(DefaultFirebaseOptions.currentPlatform,
        same(DefaultFirebaseOptions.ios));

    for (final options in [
      DefaultFirebaseOptions.android,
      DefaultFirebaseOptions.ios,
      DefaultFirebaseOptions.web,
    ]) {
      expect(options.projectId, 'rumo-app-b05fe');
      expect(options.apiKey, isNotEmpty);
    }
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.fuchsia,
  ]) {
    test('$platform não é suportada', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(() => DefaultFirebaseOptions.currentPlatform,
          throwsA(isA<UnsupportedError>()));
    });
  }
}
