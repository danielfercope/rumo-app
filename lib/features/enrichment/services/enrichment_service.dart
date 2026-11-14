import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../models/enrichment_models.dart';

/// Busca, no Backend, os dados públicos de uma empresa da carteira, uma fonte
/// por vez (cada bloco dos detalhes carrega no seu tempo).
class EnrichmentService {
  EnrichmentService(this._api);

  final ApiClient _api;

  Future<EnrichmentResult> fetch(
      String groupId, String cnpj, EnrichmentSource fonte) async {
    final data = await _api.backendRequest(
      'GET',
      'enriquecimento/${fonte.name}',
      query: {'group_id': groupId, 'cnpj': cnpj},
    ) as Map<String, dynamic>;
    return EnrichmentResult.fromJson(fonte, data);
  }
}

final enrichmentServiceProvider = Provider<EnrichmentService>(
  (ref) => EnrichmentService(ref.watch(apiClientProvider)),
);
