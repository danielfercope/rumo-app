import 'package:rumo_app/features/enrichment/models/enrichment_models.dart';
import 'package:rumo_app/features/enrichment/services/enrichment_service.dart';

/// Respostas do Backend no formato real (capturadas das fontes e reduzidas).
Map<String, dynamic> envelope(String fonte, Map<String, dynamic>? dados,
        {String status = 'ok', bool stale = false, String? mensagem}) =>
    {
      'fonte': fonte,
      'status': status,
      'origem': {
        'receita': 'Receita Federal (via BrasilAPI / Minha Receita)',
        'compras': 'Compras.gov.br e PNCP',
        'comex': 'Comex Stat (MDIC)',
        'municipio': 'IBGE',
        'google': 'Google Maps',
      }[fonte],
      'atualizado_em': '2026-11-12T22:00:00+00:00',
      'desatualizado': stale,
      'dados': dados,
      'mensagem': mensagem,
    };

final receitaJson = {
  'cnpj': '07175725000160',
  'razao_social': 'WEG EQUIPAMENTOS ELETRICOS S/A',
  'nome_fantasia': null,
  'matriz': true,
  'situacao': {
    'descricao': 'ATIVA',
    'desde': '2004-10-25',
    'motivo': 'SEM MOTIVO'
  },
  'abertura': '2004-10-25',
  'porte': 'DEMAIS',
  'natureza_juridica': 'Sociedade Anônima Fechada',
  'capital_social': 9350000000.0,
  'cnae_principal': {
    'codigo': '70.20-4/00',
    'descricao': 'Atividades de consultoria em gestão empresarial'
  },
  'cnaes_secundarios': [
    for (var i = 0; i < 8; i++)
      {'codigo': '27.10-4/0$i', 'descricao': 'Fabricação de geradores $i'}
  ],
  'simples': {'optante': null, 'desde': null, 'excluido_em': null},
  'mei': {'optante': null, 'desde': null, 'excluido_em': null},
  'regime_tributario': [
    {'ano': 2024, 'forma': 'LUCRO REAL'},
    {'ano': 2023, 'forma': 'LUCRO REAL'},
    {'ano': 2021, 'forma': 'LUCRO PRESUMIDO'},
  ],
  'socios': [
    {
      'nome': 'ALBERTO YOSHIKAZU KUBA',
      'qualificacao': 'Diretor',
      'desde': '2020-02-04',
      'faixa_etaria': 'Entre 41 a 50 anos',
      'tipo': 'PF'
    },
    {
      'nome': 'WEG S.A.',
      'qualificacao': 'Sócio',
      'desde': '2004-10-25',
      'tipo': 'PJ'
    },
  ],
  'endereco': {
    'logradouro': 'AVENIDA PREFEITO WALDEMAR GRUBBA',
    'numero': '3000',
    'complemento': null,
    'bairro': 'VILA LALAU',
    'municipio': 'JARAGUA DO SUL',
    'uf': 'SC',
    'cep': '89256900'
  },
  'codigo_municipio_ibge': 4208906,
  'telefones': ['(47) 3276-4775', '(47) 3276-4000'],
  'email': 'fiscal@weg.net',
};

final comprasJson = {
  'periodo': {'de': '2025-11-14', 'ate': '2026-11-13'},
  'sicaf': {'cadastrado': true, 'habilitado': true},
  'ultimos_12_meses': {
    'itens': 56,
    'contratacoes': 29,
    'orgaos': 20,
    'valor': 1187084.74,
    'ufs': ['BA', 'DF', 'PR', 'SP']
  },
  '12_meses_anteriores': {
    'itens': 48,
    'contratacoes': 29,
    'orgaos': 23,
    'valor': 1141028.48,
    'ufs': ['CE']
  },
  'contratacoes': [
    {
      'orgao': 'TRIBUNAL DE CONTAS DO ESTADO DO TOCANTINS',
      'uf': 'TO',
      'municipio': 'Palmas',
      'objeto': 'Software de gestão acadêmica',
      'modalidade': 'Inexigibilidade',
      'valor': 260300.0,
      'itens': 1,
      'data': '2026-04-30',
      'url': 'https://pncp.gov.br/app/editais/25053133000157/2026/35'
    }
  ],
};

final municipioJson = {
  'populacao': {'valor': 203204.0, 'ano': '2026'},
  'pib': {'valor': 15509263000.0, 'ano': '2023'},
  'pib_per_capita': {'valor': 79228.74, 'ano': '2023'},
  'municipio': 'Jaragua Do Sul (SC)',
};

final comexJson = {
  'ano': 2025,
  'municipio': 'Jaragua Do Sul (SC)',
  'exportacao': {
    'total_usd': 976239354.0,
    'produtos': [
      {
        'codigo': '8501',
        'nome': 'Motores e geradores, elétricos',
        'usd': 652797891.0,
        'participacao': 0.6687
      }
    ],
    'paises': [
      {'nome': 'Estados Unidos', 'usd': 300000000.0, 'participacao': 0.31}
    ],
  },
  'importacao': {
    'total_usd': 500000000.0,
    'produtos': [
      {
        'codigo': '7408',
        'nome': 'Fios de cobre',
        'usd': 100000000.0,
        'participacao': 0.2
      }
    ],
    'paises': [
      {'nome': 'China', 'usd': 265639575.0, 'participacao': 0.53}
    ],
  },
};

final googleJson = {
  'nome': 'WEG S/A',
  'tipo': 'Fabricante',
  'endereco': 'Av. Pref. Waldemar Grubba, 3300 - Jaraguá do Sul - SC',
  'nota': 4.7,
  'avaliacoes': 405,
  'telefone': '(47) 3276-4000',
  'site': 'http://www.weg.net/',
  'maps_url': 'https://maps.google.com/?cid=1',
  'situacao': 'Em funcionamento',
  'aberto_agora': true,
  'horarios': ['segunda-feira: 07:30–17:00'],
  'foto': {
    'url': 'https://lh3.googleusercontent.com/foto-weg',
    'autor': 'Alexandre de Castro',
    'autor_url': 'https://maps.google.com/maps/contrib/1'
  },
};

/// Serviço falso: devolve o envelope configurado por fonte.
class FakeEnrichmentService implements EnrichmentService {
  FakeEnrichmentService(this.responses);

  final Map<EnrichmentSource, Map<String, dynamic>> responses;
  final calls = <EnrichmentSource>[];

  @override
  Future<EnrichmentResult> fetch(
      String groupId, String cnpj, EnrichmentSource fonte) async {
    calls.add(fonte);
    final json =
        responses[fonte] ?? envelope(fonte.name, null, status: 'vazio');
    return EnrichmentResult.fromJson(fonte, json);
  }
}

Map<EnrichmentSource, Map<String, dynamic>> allSources() => {
      EnrichmentSource.receita: envelope('receita', receitaJson),
      EnrichmentSource.compras: envelope('compras', comprasJson),
      EnrichmentSource.municipio: envelope('municipio', municipioJson),
      EnrichmentSource.comex: envelope('comex', comexJson),
      EnrichmentSource.google: envelope('google', googleJson),
    };
