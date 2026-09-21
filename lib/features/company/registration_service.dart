import 'dart:convert';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrationService {
  final SupabaseClient _supabase;

  RegistrationService(this._supabase);

  Future<bool> cnpjExists(String cnpj) async {
    final result = await _supabase
        .from('central_data')
        .select('id')
        .eq('cnpj', cnpj)
        .maybeSingle();
    return result != null;
  }

  Future<Map<String, dynamic>> fetchEmpresaAqui(String cnpj) async {
    final response = await _supabase.functions.invoke(
      'empresa-aqui',
      body: {'cnpj': cnpj},
    );
    return (response.data as Map<String, dynamic>);
  }

  Future<({double lat, double lon, String precisao})> geocodeAddress(
      String address) async {
    const apiKey = AppConfig.googleApiKey;
    final uri = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$apiKey');

    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    final data = json.decode(response.body) as Map<String, dynamic>;

    if (data['status'] != 'OK') {
      throw 'Endereço não encontrado. Verifique o CNPJ informado.';
    }

    final loc =
        data['results'][0]['geometry']['location'] as Map<String, dynamic>;
    final locationType =
        data['results'][0]['geometry']['location_type'] as String? ??
            'APPROXIMATE';

    return (
      lat: (loc['lat'] as num).toDouble(),
      lon: (loc['lng'] as num).toDouble(),
      precisao: locationType,
    );
  }

  // Retorna true se a empresa está dentro do raio máximo (padrão: 2 km)
  bool isWithinProximity(
    double userLat,
    double userLon,
    double companyLat,
    double companyLon, {
    double maxKm = 2.0,
  }) {
    const R = 6371.0;
    final dLat = _toRad(companyLat - userLat);
    final dLon = _toRad(companyLon - userLon);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(userLat)) *
            cos(_toRad(companyLat)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final distKm = R * 2 * atan2(sqrt(a), sqrt(1 - a));
    return distKm <= maxKm;
  }

  double _toRad(double deg) => deg * pi / 180;

  Future<void> saveCompany(
    Map<String, dynamic> dadosApi,
    double lat,
    double lon,
    String precisao,
  ) async {
    final ddd = dadosApi['ddd_1'] as String? ?? '';
    final tel = dadosApi['tel_1'] as String? ?? '';
    final telefone = ddd.isNotEmpty && tel.isNotEmpty ? '$ddd$tel' : null;

    final dataAbertura = _parseDate(dadosApi['data_abertura']?.toString());

    await _supabase.from('central_data').upsert(
      {
        'cnpj': dadosApi['cnpj'],
        'nome_da_empresa': dadosApi['razao'],
        'nome_fantasia': dadosApi['fantasia'],
        'email_principal': dadosApi['email'],
        'email': dadosApi['email'],
        'url_company_page': dadosApi['site'],
        'telefone_principal': telefone,
        'endereco_completo':
            '${dadosApi['log_tipo'] ?? ''} ${dadosApi['log_nome'] ?? ''}, ${dadosApi['log_num'] ?? ''} - ${dadosApi['log_bairro'] ?? ''}',
        'tipo_de_logradouro': dadosApi['log_tipo'],
        'logradouro': dadosApi['log_nome'],
        'numero': dadosApi['log_num'],
        'bairro': dadosApi['log_bairro'],
        'municipio': dadosApi['log_municipio'],
        'uf': dadosApi['log_uf'],
        'cep': dadosApi['log_cep'],
        'natureza_juridica': dadosApi['natureza_juridica'],
        'porte_da_empresa': dadosApi['porte'],
        'situacao': dadosApi['situacao_cadastral'],
        'data_de_abertura': dataAbertura,
        'cnae_principal': dadosApi['cnae_principal'],
        'faixa_de_funcionarios': dadosApi['quadro_funcionarios'],
        'faixa_de_faturamento': dadosApi['faturamento'],
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'precisao_nivel': precisao,
      },
      onConflict: 'cnpj',
    );
  }

  String? _parseDate(String? d) {
    if (d == null || d.isEmpty || d == '00000000') return null;
    try {
      return '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}';
    } catch (_) {
      return null;
    }
  }

  Future<bool> sendToWebhook(
    Map<String, dynamic> dadosApi,
    Map<String, dynamic> dadosForm,
    String userEmail,
    String userName,
  ) async {
    const webhookUrl = AppConfig.urlWebhookCrm;

    final payload = {
      'assignments': [
        {'name': 'Primeiro nome', 'value': dadosForm['primeiro_nome']},
        {'name': 'Sobrenome', 'value': dadosForm['sobrenome']},
        {'name': 'Nome completo', 'value': dadosForm['nome_completo']},
        {'name': 'Nome do sócio', 'value': dadosForm['nome_socio']},
        {'name': 'Email', 'value': dadosForm['email_contato']},
        {
          'name': 'Nome da empresa',
          'value': dadosApi['fantasia'] ?? dadosApi['razao']
        },
        {'name': 'Razão Social', 'value': dadosApi['razao']},
        {'name': 'CNPJ', 'value': dadosApi['cnpj']},
        {
          'name': 'Número de telefone do sócio',
          'value': dadosForm['telefone_socio']
        },
        {
          'name': 'Novo lead ou cliente da base?',
          'value': dadosForm['tipo_lead']
        },
        {
          'name': 'Nome de quem está indicando o lead/cliente',
          'value': userName
        },
        {
          'name': 'E-mail de quem está indicando o lead/cliente',
          'value': userEmail
        },
        {
          'name': 'Análises a serem feitas',
          'value': dadosForm['analises_a_serem_feitas']
        },
        {
          'name': 'Endereço',
          'value':
              '${dadosApi['log_tipo'] ?? ''} ${dadosApi['log_nome'] ?? ''}, ${dadosApi['log_num'] ?? ''}'
        },
        {'name': 'Bairro', 'value': dadosApi['log_bairro']},
        {'name': 'Cidade', 'value': dadosApi['log_municipio']},
        {'name': 'Estado/Região', 'value': dadosApi['log_uf']},
        {'name': 'CEP', 'value': dadosApi['log_cep']},
        {
          'name': 'Qual é o valor da dívida?',
          'value': dadosForm['valor_divida']
        },
        {'name': 'Possuí débitos?', 'value': dadosForm['possui_debitos']},
        {'name': 'Data de validade e-CAC', 'value': dadosForm['validade_ecac']},
        {'name': 'setor da empresa', 'value': dadosForm['setor_empresa']},
        {
          'name': 'Para quem a procuração eletrônica está habilitada?',
          'value': dadosForm['para_quem_procuracao_habilitada']
        },
        {'name': 'Departamentos', 'value': dadosForm['departamentos']},
        {'name': 'Regime tributário', 'value': dadosForm['regime_tributario']},
        {'name': 'Prioridade', 'value': dadosForm['prioridade']},
        {'name': 'RUMO', 'value': true},
      ],
    };

    try {
      final response = await http
          .post(
            Uri.parse(webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}

final registrationServiceProvider = Provider<RegistrationService>((ref) {
  return RegistrationService(Supabase.instance.client);
});
