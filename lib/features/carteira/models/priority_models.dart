import '../../map/models/company_model.dart';

/// Como a ordem foi calculada (`estrategia` do backend).
enum PriorityStrategy {
  /// Poucos clientes: mais interação no CRM primeiro, empate pelo mais antigo.
  interacao,

  /// Parecença com o perfil dos clientes da organização.
  perfil,
}

/// Uma empresa da lista de prioridades (item de `GET /carteira/prioridade`).
class PriorityItem {
  final int posicao;
  final String companyId;
  final String? cnpj;
  final String? nome;
  final String? municipio;
  final String? uf;

  /// 0–100; nulo na estratégia "interacao" (não existe nota, só ordem).
  final int? nota;
  final List<String> motivos;

  const PriorityItem({
    required this.posicao,
    required this.companyId,
    this.cnpj,
    this.nome,
    this.municipio,
    this.uf,
    this.nota,
    this.motivos = const [],
  });

  factory PriorityItem.fromJson(Map<String, dynamic> json) => PriorityItem(
        posicao: json['posicao'] as int,
        companyId: json['company_id'] as String,
        cnpj: json['cnpj'] as String?,
        nome: json['nome'] as String?,
        municipio: json['municipio'] as String?,
        uf: json['uf'] as String?,
        nota: json['nota'] as int?,
        motivos: (json['motivos'] as List? ?? const []).cast<String>(),
      );

  String get local => [municipio, uf].whereType<String>().join(' / ');

  /// A lista de prioridades só traz o essencial; o detalhe abre com o que há
  /// (sem telefone, CNAE etc.) e completa pelo CRM, pelo CNPJ.
  Company toCompany() => Company(
        id: companyId,
        name: nome,
        cnpj: cnpj,
        address: local.isEmpty ? null : local,
        isClient: false,
        carteiraStatus: 'lead',
      );
}

class PriorityResult {
  /// Nulo = ainda não houve cálculo para esta organização.
  final PriorityStrategy? estrategia;
  final int nClientes;
  final int nLeads;
  final int minimoClientesPerfil;
  final List<PriorityItem> itens;

  const PriorityResult({
    required this.estrategia,
    required this.nClientes,
    required this.nLeads,
    required this.minimoClientesPerfil,
    required this.itens,
  });

  factory PriorityResult.fromJson(Map<String, dynamic> json) {
    final raw = json['estrategia'] as String?;
    return PriorityResult(
      estrategia: raw == null
          ? null
          : PriorityStrategy.values.firstWhere((e) => e.name == raw),
      nClientes: json['n_clientes'] as int? ?? 0,
      nLeads: json['n_leads'] as int? ?? 0,
      minimoClientesPerfil: json['minimo_clientes_perfil'] as int? ?? 10,
      itens: (json['itens'] as List? ?? const [])
          .map((e) => PriorityItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Quantos clientes faltam pra passar a ordenar pelo perfil.
  int get clientesFaltando =>
      (minimoClientesPerfil - nClientes).clamp(0, minimoClientesPerfil);
}

/// Como um fator pesa na nota de um lead.
enum PriorityEffect { favorece, neutro, desfavorece }

/// Uma característica da empresa (segmento, porte, cidade…) comparada ao perfil
/// dos clientes da organização.
class PriorityFactor {
  final String chave;
  final String campo;
  final String valor;
  final PriorityEffect efeito;

  /// Média ponderada do log da razão de chances: > 0 ajuda, < 0 atrapalha.
  final double contribuicao;

  /// Fração (0–1) dos clientes com este valor e da base inteira com ele.
  final double pctClientes;
  final double pctBase;
  final int clientesComValor;

  /// Quantas vezes o valor é mais comum entre os clientes que na base (nulo se
  /// a base não tem nenhuma empresa com ele).
  final double? vezes;

  const PriorityFactor({
    required this.chave,
    required this.campo,
    required this.valor,
    required this.efeito,
    required this.contribuicao,
    required this.pctClientes,
    required this.pctBase,
    required this.clientesComValor,
    this.vezes,
  });

  factory PriorityFactor.fromJson(Map<String, dynamic> json) => PriorityFactor(
        chave: json['chave'] as String,
        campo: json['campo'] as String,
        valor: json['valor'] as String,
        efeito: switch (json['efeito']) {
          'favorece' => PriorityEffect.favorece,
          'desfavorece' => PriorityEffect.desfavorece,
          _ => PriorityEffect.neutro,
        },
        contribuicao: (json['contribuicao'] as num?)?.toDouble() ?? 0,
        pctClientes: (json['pct_clientes'] as num?)?.toDouble() ?? 0,
        pctBase: (json['pct_base'] as num?)?.toDouble() ?? 0,
        clientesComValor: json['clientes_com_valor'] as int? ?? 0,
        vezes: (json['vezes'] as num?)?.toDouble(),
      );
}

/// Por que um lead tem a nota que tem (`GET /carteira/prioridade/empresa`).
class PriorityExplanation {
  final PriorityStrategy? estrategia;
  final int posicao;
  final int? nota;
  final int totalLeads;
  final int nClientes;
  final bool confiavel;
  final List<String> motivos;
  final List<PriorityFactor> fatores;

  /// Características que a empresa não tem preenchidas (não pesam na nota).
  final List<String> semDado;

  /// Sinais do CRM (estratégia por interação): interações e datas.
  final int? numInteracoes;
  final DateTime? criadoEm;
  final DateTime? ultimaInteracao;

  const PriorityExplanation({
    required this.estrategia,
    required this.posicao,
    required this.nota,
    required this.totalLeads,
    required this.nClientes,
    required this.confiavel,
    required this.motivos,
    required this.fatores,
    required this.semDado,
    this.numInteracoes,
    this.criadoEm,
    this.ultimaInteracao,
  });

  /// Nulo quando a empresa não está na lista de leads priorizados.
  static PriorityExplanation? fromJson(Map<String, dynamic> json) {
    if (json['disponivel'] != true) return null;
    final raw = json['estrategia'] as String?;
    final sinais = json['sinais'] as Map<String, dynamic>?;
    DateTime? date(Object? v) =>
        v == null ? null : DateTime.tryParse(v as String)?.toLocal();
    return PriorityExplanation(
      estrategia: raw == null
          ? null
          : PriorityStrategy.values.firstWhere((e) => e.name == raw),
      posicao: json['posicao'] as int? ?? 0,
      nota: json['nota'] as int?,
      totalLeads: json['total_leads'] as int? ?? 0,
      nClientes: json['n_clientes'] as int? ?? 0,
      confiavel: json['confiavel'] as bool? ?? true,
      motivos: (json['motivos'] as List? ?? const []).cast<String>(),
      fatores: (json['fatores'] as List? ?? const [])
          .map((e) => PriorityFactor.fromJson(e as Map<String, dynamic>))
          .toList(),
      semDado: (json['sem_dado'] as List? ?? const []).cast<String>(),
      numInteracoes: sinais?['num_interacoes'] as int?,
      criadoEm: date(sinais?['crm_criado_em']),
      ultimaInteracao: date(sinais?['ultima_interacao_em']),
    );
  }

  List<PriorityFactor> get aFavor =>
      fatores.where((f) => f.efeito == PriorityEffect.favorece).toList();
  List<PriorityFactor> get contra =>
      fatores.where((f) => f.efeito == PriorityEffect.desfavorece).toList();
}
