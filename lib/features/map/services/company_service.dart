import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/company_model.dart';

class CompanyService {
  final SupabaseClient _supabase;

  CompanyService(this._supabase);

  Future<List<Company>> getCompanies() async {
    try {
      final response = await _supabase
          .from('central_data')
          .select('id, nome_da_empresa, nome_fantasia, segmento, endereco_completo, latitude, longitude, cliente')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);

      return (response as List).map((json) => Company.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Erro ao buscar empresas: $e');
    }
  }
}
