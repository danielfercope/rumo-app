/// Diagnóstico tributário de uma empresa (GET /diagnostico/tributario):
/// provável oportunidade de recuperação de impostos pagos a mais, a partir
/// dos dados públicos. Hipótese, não parecer.
enum DiagnosisStatus { ok, vazio, indisponivel }

enum Confidence { alta, media, baixa }

Confidence _confidence(Object? raw) => switch (raw) {
      'alta' => Confidence.alta,
      'media' => Confidence.media,
      _ => Confidence.baixa,
    };

List<String> _strings(Object? raw) =>
    (raw as List? ?? const []).whereType<String>().toList();

class Evidence {
  const Evidence({required this.texto, this.fonte});

  final String texto;
  final String? fonte;

  factory Evidence.fromJson(Map<String, dynamic> j) => Evidence(
      texto: j['texto'] as String? ?? '', fonte: j['fonte'] as String?);
}

class TaxFinding {
  const TaxFinding({
    required this.id,
    required this.titulo,
    required this.resumo,
    required this.tributos,
    required this.baseLegal,
    required this.situacaoJuridica,
    required this.confianca,
    required this.periodo,
    required this.evidencias,
    required this.comoAbordar,
    required this.perguntas,
  });

  final String id;
  final String titulo;
  final String resumo;
  final List<String> tributos;
  final String? baseLegal;
  final String? situacaoJuridica;
  final Confidence confianca;
  final String? periodo;
  final List<Evidence> evidencias;
  final String? comoAbordar;
  final List<String> perguntas;

  factory TaxFinding.fromJson(Map<String, dynamic> j) => TaxFinding(
        id: j['id'] as String? ?? '',
        titulo: j['titulo'] as String? ?? '',
        resumo: j['resumo'] as String? ?? '',
        tributos: _strings(j['tributos']),
        baseLegal: j['base_legal'] as String?,
        situacaoJuridica: j['situacao_juridica'] as String?,
        confianca: _confidence(j['confianca']),
        periodo: j['periodo'] as String?,
        evidencias: (j['evidencias'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Evidence.fromJson)
            .where((e) => e.texto.isNotEmpty)
            .toList(),
        comoAbordar: j['como_abordar'] as String?,
        perguntas: _strings(j['perguntas']),
      );
}

class TaxDiagnosis {
  const TaxDiagnosis({
    required this.status,
    this.principal,
    this.outras = const [],
    this.bloqueio,
    this.fontesFaltando = const [],
    this.aviso,
  });

  final DiagnosisStatus status;
  final TaxFinding? principal;
  final List<TaxFinding> outras;

  /// Motivo de a empresa não ser lead para recuperação (inapta, MEI).
  final String? bloqueio;
  final List<String> fontesFaltando;
  final String? aviso;

  factory TaxDiagnosis.fromJson(Map<String, dynamic> j) => TaxDiagnosis(
        status: switch (j['status']) {
          'ok' => DiagnosisStatus.ok,
          'indisponivel' => DiagnosisStatus.indisponivel,
          _ => DiagnosisStatus.vazio,
        },
        principal: j['principal'] is Map<String, dynamic>
            ? TaxFinding.fromJson(j['principal'] as Map<String, dynamic>)
            : null,
        outras: (j['outras'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TaxFinding.fromJson)
            .toList(),
        bloqueio: (j['bloqueio'] as Map?)?['motivo'] as String?,
        fontesFaltando: _strings(j['fontes_faltando']),
        aviso: j['aviso'] as String?,
      );
}
