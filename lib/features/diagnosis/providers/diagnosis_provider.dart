import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tax_diagnosis.dart';
import '../services/diagnosis_service.dart';

typedef DiagnosisKey = ({String groupId, String cnpj});

/// Diagnóstico tributário de uma empresa; vive só enquanto os detalhes estão
/// abertos (as fontes por trás já ficam em cache no Backend).
final taxDiagnosisProvider =
    FutureProvider.autoDispose.family<TaxDiagnosis, DiagnosisKey>((ref, key) {
  return ref.watch(diagnosisServiceProvider).fetch(key.groupId, key.cnpj);
});
