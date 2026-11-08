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
