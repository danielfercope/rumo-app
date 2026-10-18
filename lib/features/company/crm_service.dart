import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/api_client.dart';

class CrmNote {
  final String id;
  final String body;
  final DateTime timestamp;
  final String? ownerName;

  const CrmNote({
    required this.id,
    required this.body,
    required this.timestamp,
    this.ownerName,
  });
}

class CrmContact {
  final String id;
  final String nome;
  final String? telefone;
  final String? email;

  const CrmContact({
    required this.id,
    required this.nome,
    this.telefone,
    this.email,
  });
}

// Integração com o CRM (hoje HubSpot, via backend/app/services/crm_service.py).
// Nome agnóstico de propósito — se o CRM mudar, só o backend precisa mudar;
// este contrato (4 ações, mesmo payload) continua igual.
class CrmService {
  final ApiClient _apiClient;

  CrmService(this._apiClient);

  Future<List<CrmNote>> getNotesWithOwners(String cnpj) async {
    final data = await _apiClient.backend(
      'crm',
      {'action': 'getNotesWithOwners', 'cnpj': cnpj},
    ) as Map<String, dynamic>;
    final notes = (data['notes'] as List?) ?? [];
    return notes
        .map((n) => CrmNote(
              id: n['id'] as String,
              body: n['body'] as String,
              timestamp: DateTime.parse(n['timestamp'] as String).toLocal(),
              ownerName: n['ownerName'] as String?,
            ))
        .toList();
  }

  Future<List<CrmContact>> getContacts(String cnpj) async {
    final data = await _apiClient.backend(
      'crm',
      {'action': 'getContacts', 'cnpj': cnpj},
    ) as Map<String, dynamic>;
    final contacts = (data['contacts'] as List?) ?? [];
    return contacts
        .map((c) => CrmContact(
              id: c['id'] as String,
              nome: c['nome'] as String,
              telefone: c['telefone'] as String?,
              email: c['email'] as String?,
            ))
        .toList();
  }

  Future<void> addContactToCompany({
    required String cnpj,
    required String nome,
    required String telefone,
    String? email,
  }) async {
    await _apiClient.backend('crm', {
      'action': 'addContact',
      'cnpj': cnpj,
      'nome': nome,
      'telefone': telefone,
      if (email != null && email.isNotEmpty) 'email': email,
    });
  }

  Future<void> addNoteToCompany({
    required String cnpj,
    required String noteText,
  }) async {
    await _apiClient.backend('crm', {
      'action': 'addNote',
      'cnpj': cnpj,
      'noteText': noteText,
    });
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final crmServiceProvider = Provider<CrmService>((ref) {
  return CrmService(ref.watch(apiClientProvider));
});

final crmNotesProvider = FutureProvider.autoDispose
    .family<List<CrmNote>, String>((ref, cnpj) async {
  if (cnpj.isEmpty) return [];
  return ref.read(crmServiceProvider).getNotesWithOwners(cnpj);
});

final crmContactsProvider = FutureProvider.autoDispose
    .family<List<CrmContact>, String>((ref, cnpj) async {
  if (cnpj.isEmpty) return [];
  return ref.read(crmServiceProvider).getContacts(cnpj);
});
