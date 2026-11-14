import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enrichment_models.dart';
import '../services/enrichment_service.dart';

typedef EnrichmentKey = ({
  String groupId,
  String cnpj,
  EnrichmentSource fonte,
});

/// Uma fonte de dados públicos de uma empresa. O Backend já guarda em cache;
/// aqui vive só enquanto os detalhes estão abertos.
final enrichmentProvider = FutureProvider.autoDispose
    .family<EnrichmentResult, EnrichmentKey>((ref, key) {
  return ref
      .watch(enrichmentServiceProvider)
      .fetch(key.groupId, key.cnpj, key.fonte);
});
