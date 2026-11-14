import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/company/registration_service.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockApiClient;
  late RegistrationService service;

  setUp(() {
    mockApiClient = MockApiClient();
    service = RegistrationService(mockApiClient);
  });

  group('cnpjInPortfolio', () {
    test('pergunta à carteira DA organização, não à tabela companies',
        () async {
      when(() => mockApiClient.rpc('portfolio_has_cnpj', any()))
          .thenAnswer((_) async => true);

      final result = await service.cnpjInPortfolio('g1', '12345678000199');

      expect(result, isTrue);
      final params =
          verify(() => mockApiClient.rpc('portfolio_has_cnpj', captureAny()))
              .captured
              .single as Map;
      expect(params, {'p_group_id': 'g1', 'p_cnpj': '12345678000199'});
      verifyNever(
          () => mockApiClient.get('companies', query: any(named: 'query')));
    });

    test('retorna false quando o CNPJ não está na carteira', () async {
      when(() => mockApiClient.rpc('portfolio_has_cnpj', any()))
          .thenAnswer((_) async => false);

      expect(await service.cnpjInPortfolio('g1', '1'), isFalse);
    });
  });

  group('webhookEnabledFor', () {
    test('só a organização configurada envia ao CRM do RUMO', () {
      final s = RegistrationService(mockApiClient,
          webhookGroupId: 'g-rumo', webhookUrl: 'https://crm.exemplo/hook');

      expect(s.webhookEnabledFor('g-rumo'), isTrue);
      expect(s.webhookEnabledFor('outra'), isFalse);
      expect(s.webhookEnabledFor(null), isFalse);
    });

    test('sem organização configurada, ninguém envia', () {
      final s = RegistrationService(mockApiClient,
          webhookGroupId: '', webhookUrl: 'https://crm.exemplo/hook');

      expect(s.webhookEnabledFor('g-rumo'), isFalse);
      expect(s.webhookEnabledFor(''), isFalse);
    });

    test('sem URL do webhook, ninguém envia', () {
      final s = RegistrationService(mockApiClient,
          webhookGroupId: 'g-rumo', webhookUrl: '');

      expect(s.webhookEnabledFor('g-rumo'), isFalse);
    });
  });

  group('fetchCompanyData', () {
    test("chama o backend em 'company-lookup' com o cnpj e devolve o map",
        () async {
      when(() => mockApiClient.backend('company-lookup', any())).thenAnswer(
        (_) async => {'cnpj': '12345678000199', 'razao': 'Empresa Teste'},
      );

      final result = await service.fetchCompanyData('12345678000199');

      expect(result['razao'], 'Empresa Teste');
      final captured =
          verify(() => mockApiClient.backend('company-lookup', captureAny()))
              .captured
              .single as Map;
      expect(captured['cnpj'], '12345678000199');
    });
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
