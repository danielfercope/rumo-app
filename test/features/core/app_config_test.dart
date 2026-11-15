import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/core/app_config.dart';

void main() {
  test('AppConfig usa o backend local como padrão', () {
    expect(AppConfig.apiBaseUrl, 'http://localhost:8080');
  });
}
