import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/map/providers/company_provider.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';

import '../../../helpers/active_group.dart';
import '../../../helpers/fakes.dart';

void main() {
  final options = <String, dynamic>{
    'segments': ['Varejo'],
    'products': ['Adubo'],
    'states': ['SC'],
    'cnaes': ['4712100'],
    'stateToCities': {
      'SC': ['Joinville']
    },
  };

  test('com organização ativa devolve as opções do servidor', () async {
    final repo = FakeCompanyRepository(options: options);
    final container = ProviderContainer(overrides: [
      companyRepositoryProvider.overrideWithValue(repo),
      activeGroupOverride(),
    ]);
    addTearDown(container.dispose);

    expect(await container.read(filterOptionsProvider.future), options);
    expect(repo.optionsCalls, 1);
  });

  test('sem organização ativa não há opções e o servidor nem é consultado',
      () async {
    final repo = FakeCompanyRepository(options: options);
    final container = ProviderContainer(overrides: [
      companyRepositoryProvider.overrideWithValue(repo),
      noActiveGroupOverride(),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(filterOptionsProvider.future);

    expect(result['segments'], isEmpty);
    expect(result['states'], isEmpty);
    expect(result['stateToCities'], isEmpty);
    expect(repo.optionsCalls, 0);
  });
}
