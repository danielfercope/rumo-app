import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../models/tax_diagnosis.dart';

/// Busca, no Backend, o diagnóstico tributário de uma empresa da carteira.
class DiagnosisService {
  DiagnosisService(this._api);

  final ApiClient _api;

  Future<TaxDiagnosis> fetch(String groupId, String cnpj) async {
    final data = await _api.backendRequest(
      'GET',
      'diagnostico/tributario',
      query: {'group_id': groupId, 'cnpj': cnpj},
    ) as Map<String, dynamic>;
    return TaxDiagnosis.fromJson(data);
  }
}

final diagnosisServiceProvider = Provider<DiagnosisService>(
  (ref) => DiagnosisService(ref.watch(apiClientProvider)),
);
