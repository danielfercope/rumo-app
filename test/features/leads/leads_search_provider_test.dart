import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/leads/leads_search_provider.dart';
import 'package:rumo_app/features/map/providers/company_provider.dart';
import 'package:rumo_app/features/map/data/company_repository.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeCompanyRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeCompanyRepository(companies: [buildCompany()]);
    container = ProviderContainer(overrides: [
      companyRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
  });

  group('LeadsSearchQuery', () {
    test('normalized remove espaços e isEmpty reflete isso', () {
      const q = LeadsSearchQuery(query: '  abc  ');
      expect(q.normalized, 'abc');
      expect(q.isEmpty, isFalse);
      expect(const LeadsSearchQuery(query: '   ').isEmpty, isTrue);
      expect(const LeadsSearchQuery().isEmpty, isTrue);
    });
  });

  group('leadsResultsProvider', () {
    test('retorna null sem busca e sem filtros', () async {
      expect(await container.read(leadsResultsProvider.future), isNull);
    });

    test('busca pelo texto normalizado quando há query', () async {
      container.read(leadsSearchQueryProvider.notifier).state =
          const LeadsSearchQuery(query: ' loja ', isCnpj: false);
      final result = await container.read(leadsResultsProvider.future);
      expect(result, hasLength(1));
      expect(repo.lastQuery, 'loja');
      expect(repo.lastIsCnpj, isFalse);
    });

    test('busca só com filtro (fora o raio) usa query vazia', () async {
      container.read(mapFiltersProvider.notifier).setSegment('Varejo');
      final result = await container.read(leadsResultsProvider.future);
      expect(result, isNotNull);
      expect(repo.lastQuery, '');
      expect(repo.lastFilters?.segment, 'Varejo');
    });

    test('alterar só o raio não dispara busca', () async {
      container.read(mapFiltersProvider.notifier).setRadius(50);
      expect(await container.read(leadsResultsProvider.future), isNull);
    });

    for (final setter in <String, void Function(MapFiltersNotifier)>{
      'product': (n) => n.setProduct('p'),
      'type': (n) => n.setType('client'),
      'state': (n) => n.setUf('SC'),
      'city': (n) => n.setCity('Joinville'),
      'cnae': (n) => n.setCnae('4712'),
    }.entries) {
      test('filtro ${setter.key} dispara busca', () async {
        setter.value(container.read(mapFiltersProvider.notifier));
        expect(await container.read(leadsResultsProvider.future), isNotNull);
      });
    }
  });
}
