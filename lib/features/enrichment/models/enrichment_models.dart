/// Dados públicos que enriquecem os detalhes da empresa
/// (`GET /backend/enriquecimento/{fonte}`).
library;

enum EnrichmentStatus { ok, vazio, indisponivel, desativado }

/// Fontes, na ordem em que aparecem nos detalhes.
enum EnrichmentSource { google, receita, compras, municipio, comex }

/// Envelope comum a todas as fontes.
class EnrichmentResult {
  const EnrichmentResult({
    required this.fonte,
    required this.status,
    this.origem,
    this.atualizadoEm,
    this.desatualizado = false,
    this.mensagem,
    this.dados,
  });

  final EnrichmentSource fonte;
  final EnrichmentStatus status;

  /// Quem forneceu o dado (ex.: "IBGE").
  final String? origem;
  final DateTime? atualizadoEm;

  /// A fonte não respondeu agora; isto é o último dado guardado.
  final bool desatualizado;
  final String? mensagem;
  final Map<String, dynamic>? dados;

  bool get hasData => status == EnrichmentStatus.ok && dados != null;

  factory EnrichmentResult.fromJson(
      EnrichmentSource fonte, Map<String, dynamic> json) {
    return EnrichmentResult(
      fonte: fonte,
      status: EnrichmentStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => EnrichmentStatus.indisponivel,
      ),
      origem: json['origem'] as String?,
      atualizadoEm: json['atualizado_em'] == null
          ? null
          : DateTime.tryParse(json['atualizado_em'] as String)?.toLocal(),
      desatualizado: json['desatualizado'] as bool? ?? false,
      mensagem: json['mensagem'] as String?,
      dados: json['dados'] as Map<String, dynamic>?,
    );
  }
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
double? _num(Object? v) => v is num ? v.toDouble() : null;
List<Map<String, dynamic>> _list(Object? v) =>
    (v as List? ?? const []).cast<Map<String, dynamic>>();

// ─── Receita ─────────────────────────────────────────────────────────

class Socio {
  const Socio(
      {required this.nome,
      this.qualificacao,
      this.desde,
      this.faixaEtaria,
      this.tipo});

  final String nome;
  final String? qualificacao;
  final DateTime? desde;
  final String? faixaEtaria;

  /// "PF", "PJ" ou "Estrangeiro".
  final String? tipo;
}

class Cnae {
  const Cnae({this.codigo, required this.descricao});
  final String? codigo;
  final String descricao;
}

class ReceitaData {
  const ReceitaData({
    this.razaoSocial,
    this.nomeFantasia,
    this.matriz = true,
    this.situacao,
    this.situacaoDesde,
    this.situacaoMotivo,
    this.abertura,
    this.porte,
    this.naturezaJuridica,
    this.capitalSocial,
    this.cnaePrincipal,
    this.cnaesSecundarios = const [],
    this.simplesOptante,
    this.simplesDesde,
    this.meiOptante,
    this.regimes = const [],
    this.socios = const [],
    this.endereco,
    this.telefones = const [],
    this.email,
  });

  final String? razaoSocial;
  final String? nomeFantasia;
  final bool matriz;
  final String? situacao;
  final DateTime? situacaoDesde;
  final String? situacaoMotivo;
  final DateTime? abertura;
  final String? porte;
  final String? naturezaJuridica;
  final double? capitalSocial;
  final Cnae? cnaePrincipal;
  final List<Cnae> cnaesSecundarios;
  final bool? simplesOptante;
  final DateTime? simplesDesde;
  final bool? meiOptante;

  /// (ano, forma de tributação), do mais recente ao mais antigo.
  final List<(int, String)> regimes;
  final List<Socio> socios;

  /// Endereço em uma linha.
  final String? endereco;
  final List<String> telefones;
  final String? email;

  bool get ativa => (situacao ?? '').toUpperCase() == 'ATIVA';

  /// Regime atual em texto curto: MEI > Simples > forma declarada mais recente.
  String? get regimeAtual {
    if (meiOptante == true) return 'MEI';
    if (simplesOptante == true) return 'Simples Nacional';
    if (regimes.isEmpty) return null;
    return _title(regimes.first.$2);
  }

  factory ReceitaData.fromJson(Map<String, dynamic> j) {
    final sit = j['situacao'] as Map<String, dynamic>? ?? const {};
    final simples = j['simples'] as Map<String, dynamic>? ?? const {};
    final mei = j['mei'] as Map<String, dynamic>? ?? const {};
    final end = j['endereco'] as Map<String, dynamic>? ?? const {};
    Cnae? cnae(Object? v) {
      final m = v as Map<String, dynamic>?;
      final desc = m?['descricao'] as String?;
      if (desc == null || desc.isEmpty) return null;
      return Cnae(codigo: m?['codigo'] as String?, descricao: desc);
    }

    return ReceitaData(
      razaoSocial: j['razao_social'] as String?,
      nomeFantasia: j['nome_fantasia'] as String?,
      matriz: j['matriz'] as bool? ?? true,
      situacao: sit['descricao'] as String?,
      situacaoDesde: _date(sit['desde']),
      situacaoMotivo: sit['motivo'] as String?,
      abertura: _date(j['abertura']),
      porte: j['porte'] as String?,
      naturezaJuridica: j['natureza_juridica'] as String?,
      capitalSocial: _num(j['capital_social']),
      cnaePrincipal: cnae(j['cnae_principal']),
      cnaesSecundarios: [
        for (final c in j['cnaes_secundarios'] as List? ?? const [])
          if (cnae(c) case final Cnae x) x,
      ],
      simplesOptante: simples['optante'] as bool?,
      simplesDesde: _date(simples['desde']),
      meiOptante: mei['optante'] as bool?,
      regimes: [
        for (final r in _list(j['regime_tributario']))
          if (r['ano'] is int && r['forma'] is String)
            (r['ano'] as int, r['forma'] as String),
      ],
      socios: [
        for (final s in _list(j['socios']))
          if (s['nome'] is String)
            Socio(
              nome: s['nome'] as String,
              qualificacao: s['qualificacao'] as String?,
              desde: _date(s['desde']),
              faixaEtaria: s['faixa_etaria'] as String?,
              tipo: s['tipo'] as String?,
            ),
      ],
      endereco: _oneLineAddress(end),
      telefones: (j['telefones'] as List? ?? const []).cast<String>(),
      email: j['email'] as String?,
    );
  }
}

String? _oneLineAddress(Map<String, dynamic> e) {
  String? s(String k) {
    final v = e[k] as String?;
    return v == null || v.trim().isEmpty ? null : _title(v.trim());
  }

  final rua =
      [s('logradouro'), e['numero'] as String?].whereType<String>().join(', ');
  final cidade =
      [s('municipio'), e['uf'] as String?].whereType<String>().join(' - ');
  final cep = e['cep'] as String?;
  final parts = [
    if (rua.isNotEmpty) rua,
    if (s('complemento') case final String c) c,
    if (s('bairro') case final String b) b,
    if (cidade.isNotEmpty) cidade,
    if (cep != null && cep.length == 8)
      '${cep.substring(0, 5)}-${cep.substring(5)}',
  ];
  return parts.isEmpty ? null : parts.join(', ');
}

/// "LUCRO REAL" → "Lucro Real"; mantém siglas curtas (SC, ME, S/A).
String _title(String text) => text
    .toLowerCase()
    .split(' ')
    .map((w) {
      if (w.isEmpty) return w;
      if (const {'de', 'da', 'do', 'das', 'dos', 'e'}.contains(w)) return w;
      if (w.length <= 2 || w.contains('/')) return w.toUpperCase();
      return w[0].toUpperCase() + w.substring(1);
    })
    .join(' ')
    .replaceFirstMapped(RegExp(r'^[a-z]'), (m) => m[0]!.toUpperCase());

/// Exposto pros widgets (ex.: porte "DEMAIS" → "Demais").
String titleCaseBr(String text) => _title(text);

// ─── Compras públicas ───────────────────────────────────────────────

class ComprasPeriodo {
  const ComprasPeriodo(
      {this.itens = 0,
      this.contratacoes = 0,
      this.orgaos = 0,
      this.valor = 0,
      this.ufs = const []});

  final int itens;
  final int contratacoes;
  final int orgaos;
  final double valor;
  final List<String> ufs;

  bool get vendeu => contratacoes > 0;

  factory ComprasPeriodo.fromJson(Map<String, dynamic>? j) => j == null
      ? const ComprasPeriodo()
      : ComprasPeriodo(
          itens: j['itens'] as int? ?? 0,
          contratacoes: j['contratacoes'] as int? ?? 0,
          orgaos: j['orgaos'] as int? ?? 0,
          valor: _num(j['valor']) ?? 0,
          ufs: (j['ufs'] as List? ?? const []).cast<String>(),
        );
}

class Contratacao {
  const Contratacao(
      {this.orgao,
      this.uf,
      this.municipio,
      this.objeto,
      this.modalidade,
      this.valor = 0,
      this.itens = 0,
      this.data,
      this.url});

  final String? orgao;
  final String? uf;
  final String? municipio;
  final String? objeto;
  final String? modalidade;
  final double valor;
  final int itens;
  final DateTime? data;
  final String? url;
}

class ComprasData {
  const ComprasData({
    this.sicafCadastrado,
    this.sicafHabilitado,
    this.recente = const ComprasPeriodo(),
    this.anterior,
    this.contratacoes = const [],
  });

  final bool? sicafCadastrado;
  final bool? sicafHabilitado;
  final ComprasPeriodo recente;
  final ComprasPeriodo? anterior;
  final List<Contratacao> contratacoes;

  /// Variação do valor vendido em relação aos 12 meses anteriores (0.25 =
  /// +25%). Nula sem base de comparação.
  double? get variacao {
    final a = anterior;
    if (a == null || a.valor <= 0) return null;
    return recente.valor / a.valor - 1;
  }

  factory ComprasData.fromJson(Map<String, dynamic> j) {
    final sicaf = j['sicaf'] as Map<String, dynamic>?;
    return ComprasData(
      sicafCadastrado: sicaf?['cadastrado'] as bool?,
      sicafHabilitado: sicaf?['habilitado'] as bool?,
      recente: ComprasPeriodo.fromJson(
          j['ultimos_12_meses'] as Map<String, dynamic>?),
      anterior: j['12_meses_anteriores'] == null
          ? null
          : ComprasPeriodo.fromJson(
              j['12_meses_anteriores'] as Map<String, dynamic>),
      contratacoes: [
        for (final c in _list(j['contratacoes']))
          Contratacao(
            orgao: c['orgao'] as String?,
            uf: c['uf'] as String?,
            municipio: c['municipio'] as String?,
            objeto: c['objeto'] as String?,
            modalidade: c['modalidade'] as String?,
            valor: _num(c['valor']) ?? 0,
            itens: c['itens'] as int? ?? 0,
            data: _date(c['data']),
            url: c['url'] as String?,
          ),
      ],
    );
  }
}

// ─── Economia do município ─────────────────────────────────────────

class ComexItem {
  const ComexItem(
      {required this.nome, required this.usd, required this.participacao});
  final String nome;
  final double usd;
  final double participacao;
}

class ComexFlow {
  const ComexFlow(
      {this.totalUsd = 0, this.produtos = const [], this.paises = const []});
  final double totalUsd;
  final List<ComexItem> produtos;
  final List<ComexItem> paises;

  factory ComexFlow.fromJson(Map<String, dynamic>? j) {
    List<ComexItem> items(Object? v) => [
          for (final r in _list(v))
            if (r['nome'] is String)
              ComexItem(
                nome: r['nome'] as String,
                usd: _num(r['usd']) ?? 0,
                participacao: _num(r['participacao']) ?? 0,
              ),
        ];
    return j == null
        ? const ComexFlow()
        : ComexFlow(
            totalUsd: _num(j['total_usd']) ?? 0,
            produtos: items(j['produtos']),
            paises: items(j['paises']),
          );
  }
}

class ComexData {
  const ComexData(
      {required this.ano,
      this.municipio,
      this.exportacao = const ComexFlow(),
      this.importacao = const ComexFlow()});
  final int ano;
  final String? municipio;
  final ComexFlow exportacao;
  final ComexFlow importacao;

  factory ComexData.fromJson(Map<String, dynamic> j) => ComexData(
        ano: j['ano'] as int? ?? 0,
        municipio: j['municipio'] as String?,
        exportacao:
            ComexFlow.fromJson(j['exportacao'] as Map<String, dynamic>?),
        importacao:
            ComexFlow.fromJson(j['importacao'] as Map<String, dynamic>?),
      );
}

class MunicipioData {
  const MunicipioData(
      {this.municipio,
      this.populacao,
      this.populacaoAno,
      this.pib,
      this.pibAno,
      this.pibPerCapita});
  final String? municipio;
  final double? populacao;
  final String? populacaoAno;
  final double? pib;
  final String? pibAno;
  final double? pibPerCapita;

  factory MunicipioData.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? m(String k) => j[k] as Map<String, dynamic>?;
    return MunicipioData(
      municipio: j['municipio'] as String?,
      populacao: _num(m('populacao')?['valor']),
      populacaoAno: m('populacao')?['ano'] as String?,
      pib: _num(m('pib')?['valor']),
      pibAno: m('pib')?['ano'] as String?,
      pibPerCapita: _num(m('pib_per_capita')?['valor']),
    );
  }
}

// ─── Google ─────────────────────────────────────────────────────────

class GooglePlaceData {
  const GooglePlaceData({
    this.nome,
    this.tipo,
    this.endereco,
    this.nota,
    this.avaliacoes,
    this.telefone,
    this.site,
    this.mapsUrl,
    this.situacao,
    this.abertoAgora,
    this.horarios = const [],
    this.fotoUrl,
    this.fotoAutor,
    this.fotoAutorUrl,
  });

  final String? nome;
  final String? tipo;
  final String? endereco;
  final double? nota;
  final int? avaliacoes;
  final String? telefone;
  final String? site;
  final String? mapsUrl;
  final String? situacao;
  final bool? abertoAgora;
  final List<String> horarios;

  /// Foto de capa: link temporário (vale cerca de 1 dia) e o crédito do autor,
  /// que o Google exige mostrar junto.
  final String? fotoUrl;
  final String? fotoAutor;
  final String? fotoAutorUrl;

  factory GooglePlaceData.fromJson(Map<String, dynamic> j) => GooglePlaceData(
        nome: j['nome'] as String?,
        tipo: j['tipo'] as String?,
        endereco: j['endereco'] as String?,
        nota: _num(j['nota']),
        avaliacoes: j['avaliacoes'] as int?,
        telefone: j['telefone'] as String?,
        site: j['site'] as String?,
        mapsUrl: j['maps_url'] as String?,
        situacao: j['situacao'] as String?,
        abertoAgora: j['aberto_agora'] as bool?,
        horarios: (j['horarios'] as List? ?? const []).cast<String>(),
        fotoUrl: (j['foto'] as Map<String, dynamic>?)?['url'] as String?,
        fotoAutor: (j['foto'] as Map<String, dynamic>?)?['autor'] as String?,
        fotoAutorUrl:
            (j['foto'] as Map<String, dynamic>?)?['autor_url'] as String?,
      );
}
