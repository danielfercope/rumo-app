import 'package:rumo_app/features/diagnosis/models/tax_diagnosis.dart';
import 'package:rumo_app/features/diagnosis/services/diagnosis_service.dart';

/// Resposta de GET /diagnostico/tributario de uma farmácia do Simples.
final Map<String, dynamic> diagnosisJson = {
  'status': 'ok',
  'versao': '1',
  'principal': {
    'id': 'monofasico_simples',
    'titulo': 'PIS/COFINS monofásico pago de novo no Simples',
    'resumo': 'Quem revende produto monofásico já teve o PIS/COFINS cobrado.',
    'tributos': ['PIS', 'COFINS'],
    'base_legal': 'LC 123/2006, art. 18, §4º-A',
    'situacao_juridica': 'Pacificada (previsão legal expressa)',
    'confianca': 'alta',
    'periodo': '2022–2026',
    'evidencias': [
      {
        'texto':
            'Optante do Simples Nacional: 5 anos na janela de 5 (2022–2026)',
        'fonte': 'Receita Federal'
      },
      {
        'texto': 'CNAE principal 47.71-7/01: revenda de medicamentos',
        'fonte': 'Receita Federal'
      },
    ],
    'como_abordar': 'Abordagem direta e de baixo risco.',
    'perguntas': [
      'A contabilidade separa as receitas de produtos monofásicos?',
      'Que parte do faturamento vem desses produtos?',
    ],
  },
  'outras': [
    {
      'id': 'icms_st_simples',
      'titulo': 'ICMS-ST pago de novo no DAS',
      'resumo': '…',
      'tributos': ['ICMS'],
      'confianca': 'media',
      'periodo': '2022–2026',
      'evidencias': [
        {'texto': 'CNAE principal 47.71-7/01: comércio de medicamentos'}
      ],
      'perguntas': [],
    },
  ],
  'bloqueio': null,
  'fontes_faltando': [],
  'aviso': 'Hipótese a partir de dados públicos (Receita Federal e compras '
      'públicas). Não substitui a análise das apurações da empresa.',
};

class FakeDiagnosisService implements DiagnosisService {
  FakeDiagnosisService(this.json, {this.fail = false});

  final Map<String, dynamic> json;
  bool fail;
  int calls = 0;

  @override
  Future<TaxDiagnosis> fetch(String groupId, String cnpj) async {
    calls++;
    if (fail) throw Exception('fora do ar');
    return TaxDiagnosis.fromJson(json);
  }
}
