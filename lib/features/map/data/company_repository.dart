import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_client.dart';
import '../models/company_model.dart';
import '../providers/filter_provider.dart';
import '../services/company_service.dart';

abstract class ICompanyRepository {
  Future<List<Company>> getCompanies({
    required double userLat,
    required double userLong,
    MapFilters? filters,
  });

  Future<List<Company>> searchByText({
    required String query,
    required bool isCnpj,
    MapFilters? filters,
    int limit = 200,
  });

  Future<Map<String, dynamic>> getFilterOptions();
}

class CompanyRepository implements ICompanyRepository {
  final CompanyService _service;

  CompanyRepository(this._service);

  @override
  Future<List<Company>> getCompanies({
    required double userLat,
    required double userLong,
    MapFilters? filters,
  }) =>
      _service.getCompanies(
          userLat: userLat, userLong: userLong, filters: filters);

  @override
  Future<List<Company>> searchByText({
    required String query,
    required bool isCnpj,
    MapFilters? filters,
    int limit = 200,
  }) =>
      _service.searchCompaniesText(
          query: query, isCnpj: isCnpj, filters: filters, limit: limit);

  @override
  Future<Map<String, dynamic>> getFilterOptions() =>
      _service.getFilterOptions();
}

final companyRepositoryProvider = Provider<ICompanyRepository>((ref) {
  return CompanyRepository(CompanyService(ref.watch(apiClientProvider)));
});
