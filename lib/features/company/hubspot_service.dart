import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

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
  final String _token;

  HubSpotService(this._token);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      };

  Future<String?> getCompanyId(String cnpj) async {
    final cnpjDigits = cnpj.replaceAll(RegExp(r'\D'), '');
    final response = await http
        .post(
          Uri.parse('https://api.hubspot.com/crm/v3/objects/companies/search'),
          headers: _headers,
          body: json.encode({
            'filterGroups': [
              {
                'filters': [
                  {
                    'propertyName': 'cnpj_',
                    'operator': 'EQ',
                    'value': cnpjDigits,
                  }
                ]
              }
            ],
            'properties': ['name', 'hs_object_id', 'cnpj_'],
            'limit': 1,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;
    final results = (json.decode(response.body)['results'] as List?) ?? [];
    if (results.isEmpty) return null;
    return results[0]['id'] as String?;
  }

  Future<List<Map<String, dynamic>>> _getRawNotes(String companyId) async {
    final response = await http
        .post(
          Uri.parse('https://api.hubapi.com/crm/v3/objects/notes/search'),
          headers: _headers,
          body: json.encode({
            'filterGroups': [
              {
                'filters': [
                  {
                    'propertyName': 'associations.company',
                    'operator': 'EQ',
                    'value': companyId,
                  }
                ]
              }
            ],
            'properties': ['hs_note_body', 'hs_timestamp', 'hubspot_owner_id'],
            'sorts': [
              {'propertyName': 'hs_timestamp', 'direction': 'DESCENDING'}
            ],
            'limit': 100,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return [];
    return List<Map<String, dynamic>>.from(
        (json.decode(response.body)['results'] as List?) ?? []);
  }

  // Retorna mapa de ownerId → "Nome Sobrenome"
  Future<Map<String, String>> _getOwners() async {
    final response = await http
        .get(
          Uri.parse('https://api.hubapi.com/crm/v3/owners?limit=200'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return {};

    final results = (json.decode(response.body)['results'] as List?) ?? [];
    return {
      for (final o in results)
        (o['id'] ?? '').toString(): '${o['firstName'] ?? ''} ${o['lastName'] ?? ''}'.trim(),
    };
  }

  Future<List<HubSpotNote>> getNotesWithOwners(String cnpj) async {
    final companyId = await getCompanyId(cnpj);
    if (companyId == null) return [];

    final rawNotes = await _getRawNotes(companyId);
    if (rawNotes.isEmpty) return [];

    final owners = await _getOwners();

    return rawNotes.map((n) {
      final props = n['properties'] as Map<String, dynamic>? ?? {};
      final body = _stripHtml(props['hs_note_body'] as String? ?? '');
      final tsRaw = props['hs_timestamp'] as String? ?? '';
      final ownerId = (props['hubspot_owner_id'] ?? '').toString();

      DateTime ts;
      try {
        ts = DateTime.parse(tsRaw).toLocal();
      } catch (_) {
        ts = DateTime.now();
      }

      return HubSpotNote(
        id: (n['id'] ?? '').toString(),
        body: body,
        timestamp: ts,
        ownerName: owners[ownerId]?.isNotEmpty == true ? owners[ownerId] : null,
      );
    }).where((note) => note.body.isNotEmpty).toList();
  }

  String _stripHtml(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').trim();

  /// Busca contatos associados à company pelo CNPJ.
  Future<List<HubSpotContact>> getContacts(String cnpj) async {
    final companyId = await getCompanyId(cnpj);
    if (companyId == null) return [];

    final response = await http
        .post(
          Uri.parse('https://api.hubapi.com/crm/v3/objects/contacts/search'),
          headers: _headers,
          body: json.encode({
            'filterGroups': [
              {
                'filters': [
                  {
                    'propertyName': 'associations.company',
                    'operator': 'EQ',
                    'value': companyId,
                  }
                ]
              }
            ],
            'properties': ['firstname', 'lastname', 'phone', 'email'],
            'limit': 50,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return [];

    final results = (json.decode(response.body)['results'] as List?) ?? [];
    return results.map((r) {
      final props = r['properties'] as Map<String, dynamic>? ?? {};
      final first = (props['firstname'] as String? ?? '').trim();
      final last = (props['lastname'] as String? ?? '').trim();
      final nome = [first, last].where((s) => s.isNotEmpty).join(' ');
      return HubSpotContact(
        id: (r['id'] ?? '').toString(),
        nome: nome.isNotEmpty ? nome : 'Contato sem nome',
        telefone: props['phone'] as String?,
        email: props['email'] as String?,
      );
    }).toList();
  }

  /// Cria um contato no HubSpot e o associa à company pelo CNPJ.
  Future<void> addContactToCompany({
    required String cnpj,
    required String nome,
    required String telefone,
    String? email,
  }) async {
    final companyId = await getCompanyId(cnpj);
    if (companyId == null) throw Exception('Empresa não encontrada no CRM.');

    final contactProps = <String, dynamic>{
      'firstname': nome,
      'phone': telefone,
      'hs_marketable_status': 'false',
    };
    if (email != null && email.isNotEmpty) contactProps['email'] = email;

    final createResp = await http
        .post(
          Uri.parse('https://api.hubapi.com/crm/v3/objects/contacts'),
          headers: _headers,
          body: json.encode({'properties': contactProps}),
        )
        .timeout(const Duration(seconds: 10));

    if (createResp.statusCode != 201) {
      throw Exception('Erro ao criar contato no CRM (${createResp.statusCode}).');
    }

    final contactId = json.decode(createResp.body)['id'] as String;

    final assocResp = await http
        .post(
          Uri.parse(
              'https://api.hubapi.com/crm/v3/associations/contacts/companies/batch/create'),
          headers: _headers,
          body: json.encode({
            'inputs': [
              {
                'from': {'id': contactId},
                'to': {'id': companyId},
                'type': 'contact_to_company',
              }
            ]
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (assocResp.statusCode != 201 && assocResp.statusCode != 200) {
      throw Exception('Contato criado mas não foi possível associar à empresa.');
    }
  }

  /// Cria uma nota no HubSpot e a associa à company pelo CNPJ.
  Future<void> addNoteToCompany({
    required String cnpj,
    required String noteText,
  }) async {
    final companyId = await getCompanyId(cnpj);
    if (companyId == null) throw Exception('Empresa não encontrada no CRM.');

    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

    final createResp = await http
        .post(
          Uri.parse('https://api.hubapi.com/crm/v3/objects/notes'),
          headers: _headers,
          body: json.encode({
            'properties': {
              'hs_note_body': noteText,
              'hs_timestamp': timestamp,
            }
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (createResp.statusCode != 201) {
      throw Exception('Erro ao criar nota no CRM (${createResp.statusCode}).');
    }

    final noteId = json.decode(createResp.body)['id'] as String;

    final assocResp = await http
        .put(
          Uri.parse(
              'https://api.hubapi.com/crm/v4/objects/notes/$noteId/associations/default/companies/$companyId'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 10));

    if (assocResp.statusCode != 200 && assocResp.statusCode != 201) {
      throw Exception('Nota criada mas não foi possível associar à empresa.');
    }
  }
}

// ─── Providers ──────────────────────────────────────────────────────────────

final hubspotServiceProvider = Provider<HubSpotService>((ref) {
  return HubSpotService(dotenv.env['HUBSPOT_TOKEN'] ?? '');
});

final hubspotNotesProvider =
    FutureProvider.autoDispose.family<List<HubSpotNote>, String>((ref, cnpj) async {
  if (cnpj.isEmpty) return [];
  return ref.read(hubspotServiceProvider).getNotesWithOwners(cnpj);
});

final hubspotContactsProvider =
    FutureProvider.autoDispose.family<List<HubSpotContact>, String>((ref, cnpj) async {
  if (cnpj.isEmpty) return [];
  return ref.read(hubspotServiceProvider).getContacts(cnpj);
});
