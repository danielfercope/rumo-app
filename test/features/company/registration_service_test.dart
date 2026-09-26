import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/company/registration_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late RegistrationService service;

  setUp(() {
    service = RegistrationService(MockSupabaseClient());
  });

  group('isWithinProximity', () {
    test('retorna true quando as coordenadas são idênticas (distância zero)',
        () {
      final result =
          service.isWithinProximity(-26.4843, -49.0717, -26.4843, -49.0717);
      expect(result, isTrue);
    });

    test(
        'retorna true para uma distância pequena dentro do raio padrão de 2 km',
        () {
      // ~1.1 km de diferença na latitude (aprox. 0.01 grau ≈ 1.1 km)
      final result =
          service.isWithinProximity(-26.4843, -49.0717, -26.4943, -49.0717);
      expect(result, isTrue);
    });

    test('retorna false para uma distância maior que o raio padrão de 2 km',
        () {
      // ~11 km de diferença na latitude (0.1 grau ≈ 11 km)
      final result =
          service.isWithinProximity(-26.4843, -49.0717, -26.5843, -49.0717);
      expect(result, isFalse);
    });

    test('respeita um maxKm customizado', () {
      final result = service.isWithinProximity(
        -26.4843,
        -49.0717,
        -26.5843,
        -49.0717,
        maxKm: 20,
      );
      expect(result, isTrue);
    });

    test(
        'uma distância logo abaixo do limite (1.9 km) fica dentro do raio de 2 km',
        () {
      // Para diferença pura de latitude, a distância haversine se reduz a
      // R * dLat(rad), então dá pra calcular o deslocamento exato em graus.
      const distanciaAlvoKm = 1.9;
      const dLatGraus = (distanciaAlvoKm / 6371.0) * (180 / 3.141592653589793);

      final result = service.isWithinProximity(0, 0, dLatGraus, 0, maxKm: 2.0);
      expect(result, isTrue);
    });

    test(
        'uma distância logo acima do limite (2.1 km) fica fora do raio de 2 km',
        () {
      const distanciaAlvoKm = 2.1;
      const dLatGraus = (distanciaAlvoKm / 6371.0) * (180 / 3.141592653589793);

      final result = service.isWithinProximity(0, 0, dLatGraus, 0, maxKm: 2.0);
      expect(result, isFalse);
    });
  });
}
