import 'package:flutter/foundation.dart';
import '../../../core/services/api_client.dart';
import '../models/company_model.dart';
import '../providers/filter_provider.dart';

class CompanyService {
  final ApiClient _apiClient;

  CompanyService(this._apiClient);

  bool? _isClientFromType(MapFilters? filters) {
    if (filters?.type == 'client') return true;
    if (filters?.type == 'lead') return false;
    return null;
  }

  Future<List<Company>> getCompanies({
    required double userLat,
    required double userLong,
    MapFilters? filters,
  }) async {
    final params = <String, dynamic>{
      'p_lat': userLat,
      'p_lon': userLong,
      'p_radius_km': filters?.radius ?? 5.0,
      if (filters?.segment?.isNotEmpty == true) 'p_segment': filters!.segment,
      if (filters?.product?.isNotEmpty == true) 'p_product': filters!.product,
      if (filters?.state?.isNotEmpty == true) 'p_state': filters!.state,
      if (filters?.city?.isNotEmpty == true) 'p_city': filters!.city,
      if (filters?.cnae?.isNotEmpty == true) 'p_cnae': filters!.cnae,
      if (_isClientFromType(filters) != null)
        'p_is_client': _isClientFromType(filters),
    };

    debugPrint('RPC search_companies (raio) params: $params');
    final response = await _apiClient.rpc('search_companies', params);
    final list = response as List;
    debugPrint('search_companies retornou ${list.length} registros');
    return list
        .map((e) => Company.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Company>> searchCompaniesText({
    required String query,
    required bool isCnpj,
    MapFilters? filters,
    int limit = 200,
  }) async {
    final params = <String, dynamic>{
      'p_query': query,
      'p_limit': limit,
      if (filters?.segment?.isNotEmpty == true) 'p_segment': filters!.segment,
      if (filters?.product?.isNotEmpty == true) 'p_product': filters!.product,
      if (filters?.state?.isNotEmpty == true) 'p_state': filters!.state,
      if (filters?.city?.isNotEmpty == true) 'p_city': filters!.city,
      if (filters?.cnae?.isNotEmpty == true) 'p_cnae': filters!.cnae,
      if (_isClientFromType(filters) != null)
        'p_is_client': _isClientFromType(filters),
    };

    debugPrint('RPC search_companies (texto) params: $params');
    final response = await _apiClient.rpc('search_companies', params);
    final list = response as List;
    debugPrint('search_companies retornou ${list.length} registros');
    return list
        .map((e) => Company.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getFilterOptions() async {
    final response = await _apiClient.rpc('get_filter_options', {});
    final data = response as Map<String, dynamic>;
    return {
      'segments': List<String>.from(data['segments'] ?? []),
      'products': List<String>.from(data['products'] ?? []),
      'states': List<String>.from(data['states'] ?? []),
      'cnaes': List<String>.from(data['cnaes'] ?? []),
      'stateToCities':
          (data['state_to_cities'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, List<String>.from(value as List)),
      ),
    };
  }
}
