import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/api_client.dart';
import '../groups/providers/group_provider.dart';

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
  final String? Function() _activeGroupId;

  /// [activeGroupId] devolve a organização ativa: o Backend confere que o
  /// usuário é membro e que o CNPJ está na carteira dela.
  CrmService(this._apiClient, {String? Function()? activeGroupId})
      : _activeGroupId = activeGroupId ?? (() => null);

  Future<dynamic> _call(Map<String, dynamic> body) {
    final groupId = _activeGroupId();
    if (groupId == null) {
      throw StateError('Entre em uma organização para usar o CRM.');
    }
    return _apiClient.backend('crm', {'group_id': groupId, ...body});
  }

  Future<List<CrmNote>> getNotesWithOwners(String cnpj) async {
    final data = await _call(
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
    final data = await _call(
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
    await _call({
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
    await _call({
      'action': 'addNote',
      'cnpj': cnpj,
      'noteText': noteText,
    });
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final crmServiceProvider = Provider<CrmService>((ref) {
  return CrmService(
    ref.watch(apiClientProvider),
    // lido a cada chamada: trocar de organização vale na hora
    activeGroupId: () => ref.read(activeGroupProvider)?.group.id,
  );
});

final crmNotesProvider =
    FutureProvider.autoDispose.family<List<CrmNote>, String>((ref, cnpj) async {
  if (cnpj.isEmpty) return [];
  return ref.read(crmServiceProvider).getNotesWithOwners(cnpj);
});

final crmContactsProvider = FutureProvider.autoDispose
    .family<List<CrmContact>, String>((ref, cnpj) async {
  if (cnpj.isEmpty) return [];
  return ref.read(crmServiceProvider).getContacts(cnpj);
});
