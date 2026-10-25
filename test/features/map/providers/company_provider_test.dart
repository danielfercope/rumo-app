import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rumo_app/features/map/providers/company_provider.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';
import 'package:rumo_app/features/map/providers/location_provider.dart';

import '../../../helpers/fakes.dart';

Position _pos(double lat, double lon) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime(2026),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

void main() {
  test('companiesProvider consulta o repositório com a posição e os filtros',
      () async {
    final repo = FakeCompanyRepository(companies: [buildCompany()]);
    final container = ProviderContainer(overrides: [
      companyRepositoryProvider.overrideWithValue(repo),
      locationProvider.overrideWith((ref) async => _pos(-26.1, -49.2)),
    ]);
    addTearDown(container.dispose);

    container.read(mapFiltersProvider.notifier).setSegment('Varejo');
    await container.read(locationProvider.future);
    final result = await container.read(companiesProvider.future);

    expect(result, hasLength(1));
    expect(repo.lastLat, -26.1);
    expect(repo.lastFilters?.segment, 'Varejo');
  });

  test('companiesProvider devolve lista vazia enquanto a posição não chegou', () async {
    final repo = FakeCompanyRepository(companies: [buildCompany()]);
    final container = ProviderContainer(overrides: [
      companyRepositoryProvider.overrideWithValue(repo),
      locationProvider.overrideWith((ref) => Completer<Position>().future),
    ]);
    addTearDown(container.dispose);

    expect(await container.read(companiesProvider.future), isEmpty);
    expect(repo.lastLat, isNull);
  });
}
