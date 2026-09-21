import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HubSpotNote {
  final String id;
  final String body;
  final DateTime timestamp;
  final String? ownerName;

  const HubSpotNote({
    required this.id,
    required this.body,
    required this.timestamp,
    this.ownerName,
  });
}

class HubSpotContact {
  final String id;
  final String nome;
  final String? telefone;
  final String? email;

  const HubSpotContact({
    required this.id,
    required this.nome,
    this.telefone,
    this.email,
  });
}

class HubSpotService {
  final SupabaseClient _supabase;

  HubSpotService(this._supabase);

  Future<List<HubSpotNote>> getNotesWithOwners(String cnpj) async {
    final response = await _supabase.functions.invoke(
      'hubspot',
      body: {'action': 'getNotesWithOwners', 'cnpj': cnpj},
    );
    final data = response.data as Map<String, dynamic>;
    final notes = (data['notes'] as List?) ?? [];
    return notes
        .map((n) => HubSpotNote(
              id: n['id'] as String,
              body: n['body'] as String,
              timestamp: DateTime.parse(n['timestamp'] as String).toLocal(),
              ownerName: n['ownerName'] as String?,
            ))
        .toList();
  }

  Future<List<HubSpotContact>> getContacts(String cnpj) async {
    final response = await _supabase.functions.invoke(
      'hubspot',
      body: {'action': 'getContacts', 'cnpj': cnpj},
    );
    final data = response.data as Map<String, dynamic>;
    final contacts = (data['contacts'] as List?) ?? [];
    return contacts
        .map((c) => HubSpotContact(
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
    await _supabase.functions.invoke(
      'hubspot',
      body: {
        'action': 'addContact',
        'cnpj': cnpj,
        'nome': nome,
        'telefone': telefone,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );
  }

  Future<void> addNoteToCompany({
    required String cnpj,
    required String noteText,
  }) async {
    await _supabase.functions.invoke(
      'hubspot',
      body: {
        'action': 'addNote',
        'cnpj': cnpj,
        'noteText': noteText,
      },
    );
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final hubspotServiceProvider = Provider<HubSpotService>((ref) {
  return HubSpotService(Supabase.instance.client);
});

final hubspotNotesProvider = FutureProvider.autoDispose
    .family<List<HubSpotNote>, String>((ref, cnpj) async {
  if (cnpj.isEmpty) return [];
  return ref.read(hubspotServiceProvider).getNotesWithOwners(cnpj);
});

final hubspotContactsProvider = FutureProvider.autoDispose
    .family<List<HubSpotContact>, String>((ref, cnpj) async {
  if (cnpj.isEmpty) return [];
  return ref.read(hubspotServiceProvider).getContacts(cnpj);
});
