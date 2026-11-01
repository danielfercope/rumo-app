import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/core/services/analytics_service.dart';

void main() {
  test('analyticsProvider sem Firebase inicializado falha ao ser lido', () {
    // FirebaseAnalytics.instance exige Firebase.initializeApp() (feito no
    // main.dart); nos testes não há app padrão, então a leitura levanta.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(() => container.read(analyticsProvider), throwsA(anything));
  });
}
