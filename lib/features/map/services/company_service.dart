import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;
import '../models/company_model.dart';
import '../providers/filter_provider.dart';

class CompanyService {
  final SupabaseClient _supabase;

  CompanyService(this._supabase);

  Future<List<Company>> getCompaniesInRadius({
    required double userLat,
    required double userLong,
    required double radiusKm,
    MapFilters? filters,
  }) async {
    try {
      print('DEBUG: [CompanyService] Iniciando busca (versão sem Bounding Box)...');
      
      var query = _supabase.from('central_data').select('*');

      if (filters != null) {
        if (filters.segment != null && filters.segment!.isNotEmpty) {
          query = query.eq('segmento', filters.segment!);
        }
        if (filters.product != null && filters.product!.isNotEmpty) {
          query = query.eq('produto', filters.product!);
        }
        if (filters.type != null) {
          if (filters.type == 'client') {
            query = query.eq('cliente', true);
          } else if (filters.type == 'lead') {
            query = query.eq('cliente', false);
          }
        }
        if (filters.state != null && filters.state!.isNotEmpty) {
          query = query.eq('uf', filters.state!);
        }
        if (filters.city != null && filters.city!.isNotEmpty) {
          query = query.eq('municipio', filters.city!);
        }
        if (filters.cnae != null && filters.cnae!.isNotEmpty) {
          query = query.eq('cnae_principal', filters.cnae!);
        }
      }

      final response = await query;
      final list = response as List;
      print('DEBUG: [Supabase] Registros brutos retornados: ${list.length}');

      final List<Company> companiesInRange = [];
      
      for (var item in list) {
        final c = Company.fromJson(item);
        if (c.latitude != null && c.longitude != null) {
          double dist = _calculateDistance(userLat, userLong, c.latitude!, c.longitude!);
          
          if (dist <= radiusKm) {
            c.distance = dist;
            companiesInRange.add(c);
          }
        }
      }

      print('DEBUG: [Summary] Total qualificado: ${companiesInRange.length}');
      return companiesInRange;
    } catch (e) {
      print('DEBUG: [CompanyService] ERRO: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getFilterOptions() async {
    try {
      print('DEBUG: [CompanyService] Buscando todas as opções de filtros...');
      final response = await _supabase
          .from('central_data')
          .select('segmento, produto, uf, municipio, cnae_principal');

      final data = response as List;
      
      final Map<String, Set<String>> stateToCities = {};
      final Set<String> segments = {};
      final Set<String> products = {};
      final Set<String> states = {};
      final Set<String> cnaes = {};

      for (var item in data) {
        final uf = (item['uf']?.toString() ?? '').trim();
        final mun = (item['municipio']?.toString() ?? '').trim();
        final seg = (item['segmento']?.toString() ?? '').trim();
        final prod = (item['produto']?.toString() ?? '').trim();
        final cnae = (item['cnae_principal']?.toString() ?? '').trim();

        if (uf.isNotEmpty) {
          states.add(uf);
          if (mun.isNotEmpty) {
            stateToCities.putIfAbsent(uf, () => {}).add(mun);
          }
        }
        if (seg.isNotEmpty) segments.add(seg);
        if (prod.isNotEmpty) products.add(prod);
        if (cnae.isNotEmpty) cnaes.add(cnae);
      }

      return {
        'segments': segments.toList()..sort(),
        'products': products.toList()..sort(),
        'states': states.toList()..sort(),
        'stateToCities': stateToCities.map((key, value) => MapEntry(key, value.toList()..sort())),
        'cnaes': cnaes.toList()..sort(),
      };
    } catch (e) {
      print('DEBUG: [CompanyService] Erro ao buscar opções: $e');
      return {};
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) *
            (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a));
  }
}
