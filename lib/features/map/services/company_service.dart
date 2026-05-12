import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/company_model.dart';
import '../providers/filter_provider.dart';

class CompanyService {
  final SupabaseClient _supabase;

  CompanyService(this._supabase);

  Future<List<Company>> getCompanies({
    required double userLat,
    required double userLong,
    MapFilters? filters,
  }) async {
    bool? isClient;
    if (filters?.type == 'client') isClient = true;
    if (filters?.type == 'lead') isClient = false;

    final params = <String, dynamic>{
      'p_lat': userLat,
      'p_lon': userLong,
      'p_radius_km': filters?.radius ?? 5.0,
      if (filters?.segment?.isNotEmpty == true) 'p_segment': filters!.segment,
      if (filters?.product?.isNotEmpty == true) 'p_product': filters!.product,
      if (filters?.state?.isNotEmpty == true)   'p_state':   filters!.state,
      if (filters?.city?.isNotEmpty == true)    'p_city':    filters!.city,
      if (filters?.cnae?.isNotEmpty == true)    'p_cnae':    filters!.cnae,
      if (isClient != null) 'p_is_client': isClient,
    };

    debugPrint('RPC params: $params');
    final response = await _supabase.rpc('search_companies_in_radius', params: params);
    final list = response as List;
    debugPrint('RPC retornou ${list.length} registros');
    return list.map((e) => Company.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Company>> searchCompaniesText({
    required String query,
    required bool isCnpj,
    MapFilters? filters,
    int limit = 200,
  }) async {
    bool? isClient;
    if (filters?.type == 'client') isClient = true;
    if (filters?.type == 'lead') isClient = false;

    final params = <String, dynamic>{
      'p_query': query,
      'p_is_cnpj': isCnpj,
      'p_limit': limit,
      if (filters?.segment?.isNotEmpty == true) 'p_segment': filters!.segment,
      if (filters?.product?.isNotEmpty == true) 'p_product': filters!.product,
      if (filters?.state?.isNotEmpty == true)   'p_state':   filters!.state,
      if (filters?.city?.isNotEmpty == true)    'p_city':    filters!.city,
      if (filters?.cnae?.isNotEmpty == true)    'p_cnae':    filters!.cnae,
      if (isClient != null) 'p_is_client': isClient,
    };

    debugPrint('RPC text params: $params');
    final response = await _supabase.rpc('search_companies_text', params: params);
    final list = response as List;
    debugPrint('RPC text retornou ${list.length} registros');
    return list.map((e) => Company.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getFilterOptions() async {
    final response = await _supabase.rpc('get_filter_options');
    final data = response as Map<String, dynamic>;
    return {
      'segments':     List<String>.from(data['segments']  ?? []),
      'products':     List<String>.from(data['products']  ?? []),
      'states':       List<String>.from(data['states']    ?? []),
      'cnaes':        List<String>.from(data['cnaes']     ?? []),
      'stateToCities': (data['state_to_cities'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, List<String>.from(value as List)),
      ),
    };
  }
}
