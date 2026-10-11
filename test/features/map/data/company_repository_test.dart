import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/map/data/company_repository.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';
import 'package:rumo_app/features/map/services/company_service.dart';

class MockCompanyService extends Mock implements CompanyService {}

void main() {
  late MockCompanyService mockService;
  late CompanyRepository repository;

  setUp(() {
    mockService = MockCompanyService();
    repository = CompanyRepository(mockService);
  });

  test('getCompanies delega pro CompanyService com os mesmos argumentos',
      () async {
    final filters = MapFilters(segment: 'Varejo');
    when(() => mockService.getCompanies(
          userLat: any(named: 'userLat'),
          userLong: any(named: 'userLong'),
          filters: any(named: 'filters'),
        )).thenAnswer((_) async => <Company>[]);

    await repository.getCompanies(
        userLat: -26.4, userLong: -49.0, filters: filters);

    verify(() => mockService.getCompanies(
          userLat: -26.4,
          userLong: -49.0,
          filters: filters,
        )).called(1);
  });

  test('searchByText delega pro CompanyService com os mesmos argumentos',
      () async {
    when(() => mockService.searchCompaniesText(
          query: any(named: 'query'),
          isCnpj: any(named: 'isCnpj'),
          filters: any(named: 'filters'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => <Company>[]);

    await repository.searchByText(query: 'teste', isCnpj: false, limit: 50);

    verify(() => mockService.searchCompaniesText(
          query: 'teste',
          isCnpj: false,
          filters: null,
          limit: 50,
        )).called(1);
  });

  test('getFilterOptions delega pro CompanyService', () async {
    when(() => mockService.getFilterOptions())
        .thenAnswer((_) async => {'segments': []});

    final result = await repository.getFilterOptions();

    expect(result, {'segments': []});
    verify(() => mockService.getFilterOptions()).called(1);
  });
}
