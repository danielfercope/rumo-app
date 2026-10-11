import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';
import 'package:rumo_app/features/map/services/company_service.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockApiClient;
  late CompanyService service;

  setUp(() {
    mockApiClient = MockApiClient();
    service = CompanyService(mockApiClient);
  });

  group('getCompanies', () {
    test('envia lat/lon/raio e mapeia a resposta da RPC em Company', () async {
      when(() => mockApiClient.rpc('search_companies', any())).thenAnswer(
        (_) async => [
          {'id': '1', 'cnpj': '12345678000199', 'distance_km': 1.2}
        ],
      );

      final result =
          await service.getCompanies(userLat: -26.4, userLong: -49.0);

      expect(result, hasLength(1));
      expect(result.first.cnpj, '12345678000199');
      expect(result.first.distance, 1.2);

      final params =
          verify(() => mockApiClient.rpc('search_companies', captureAny()))
              .captured
              .single as Map;
      expect(params['p_lat'], -26.4);
      expect(params['p_lon'], -49.0);
      expect(params['p_radius_km'], 5.0);
    });

    test('inclui os filtros não vazios e omite os vazios/nulos', () async {
      when(() => mockApiClient.rpc('search_companies', any()))
          .thenAnswer((_) async => []);

      await service.getCompanies(
        userLat: -26.4,
        userLong: -49.0,
        filters: MapFilters(segment: 'Varejo', radius: 10, type: 'client'),
      );

      final params =
          verify(() => mockApiClient.rpc('search_companies', captureAny()))
              .captured
              .single as Map;
      expect(params['p_segment'], 'Varejo');
      expect(params['p_radius_km'], 10.0);
      expect(params['p_is_client'], true);
      expect(params.containsKey('p_product'), isFalse);
      expect(params.containsKey('p_state'), isFalse);
    });

    test('type "lead" nos filtros vira p_is_client: false', () async {
      when(() => mockApiClient.rpc('search_companies', any()))
          .thenAnswer((_) async => []);

      await service.getCompanies(
        userLat: -26.4,
        userLong: -49.0,
        filters: MapFilters(type: 'lead'),
      );

      final params =
          verify(() => mockApiClient.rpc('search_companies', captureAny()))
              .captured
              .single as Map;
      expect(params['p_is_client'], false);
    });
  });

  group('searchCompaniesText', () {
    test('envia p_query/p_limit sem p_lat/p_lon', () async {
      when(() => mockApiClient.rpc('search_companies', any()))
          .thenAnswer((_) async => []);

      await service.searchCompaniesText(query: 'Empresa Teste', isCnpj: false);

      final params =
          verify(() => mockApiClient.rpc('search_companies', captureAny()))
              .captured
              .single as Map;
      expect(params['p_query'], 'Empresa Teste');
      expect(params['p_limit'], 200);
      expect(params.containsKey('p_lat'), isFalse);
      expect(params.containsKey('p_lon'), isFalse);
    });
  });

  group('getFilterOptions', () {
    test('converte state_to_cities (snake_case) em stateToCities', () async {
      when(() => mockApiClient.rpc('get_filter_options', {})).thenAnswer(
        (_) async => {
          'segments': ['Varejo'],
          'products': ['SaveID'],
          'states': ['SC'],
          'cnaes': [],
          'state_to_cities': {
            'SC': ['Joinville']
          },
        },
      );

      final result = await service.getFilterOptions();

      expect(result['segments'], ['Varejo']);
      expect(result['stateToCities'], {
        'SC': ['Joinville']
      });
    });
  });
}
