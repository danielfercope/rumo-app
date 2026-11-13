class CrmOption {
  final String value;
  final String label;

  const CrmOption({required this.value, required this.label});

  factory CrmOption.fromJson(Map<String, dynamic> json) => CrmOption(
        value: json['value'] as String,
        label: json['label'] as String? ?? json['value'] as String,
      );
}

/// Propriedade de empresa do CRM, pra o usuário escolher qual é o CNPJ e qual
/// é o estágio. `options` só vem em propriedades de lista (ex.: estágio).
class CrmProperty {
  final String name;
  final String label;
  final String type;
  final List<CrmOption> options;

  const CrmProperty({
    required this.name,
    required this.label,
    required this.type,
    this.options = const [],
  });

  factory CrmProperty.fromJson(Map<String, dynamic> json) => CrmProperty(
        name: json['name'] as String,
        label: json['label'] as String? ?? json['name'] as String,
        type: json['type'] as String? ?? 'string',
        options: (json['options'] as List? ?? [])
            .map((e) => CrmOption.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Como ler as empresas do CRM: qual propriedade guarda o CNPJ, qual guarda o
/// estágio, e que valores do estágio significam cliente/perdido (todo o resto
/// é lead). É o mesmo formato de `crm_conexoes.mapeamento`.
class CrmMapping {
  final String campoCnpj;
  final String campoStatus;
  final List<String> valoresCliente;
  final List<String> valoresPerdido;

  const CrmMapping({
    required this.campoCnpj,
    required this.campoStatus,
    this.valoresCliente = const [],
    this.valoresPerdido = const [],
  });

  Map<String, dynamic> toJson() => {
        'campo_cnpj': campoCnpj,
        'campo_status': campoStatus,
        'status': {
          'cliente': valoresCliente,
          'perdido': valoresPerdido,
        },
      };
}

/// O que seria importado, antes de o usuário confirmar a conexão.
class CrmPreview {
  final int totalComCnpj;
  final int validos;
  final int cnpjInvalido;
  final int clientes;
  final int leads;
  final int perdidos;
  final bool truncado;

  const CrmPreview({
    required this.totalComCnpj,
    required this.validos,
    required this.cnpjInvalido,
    required this.clientes,
    required this.leads,
    required this.perdidos,
    required this.truncado,
  });

  factory CrmPreview.fromJson(Map<String, dynamic> json) {
    final porStatus = json['por_status'] as Map<String, dynamic>? ?? {};
    return CrmPreview(
      totalComCnpj: json['total_com_cnpj'] as int? ?? 0,
      validos: json['validos'] as int? ?? 0,
      cnpjInvalido: json['cnpj_invalido'] as int? ?? 0,
      clientes: porStatus['cliente'] as int? ?? 0,
      leads: porStatus['lead'] as int? ?? 0,
      perdidos: porStatus['perdido'] as int? ?? 0,
      truncado: json['truncado'] as bool? ?? false,
    );
  }
}

enum CrmConnectionStatus { importando, conectado, erro }

/// Conexão da organização com o CRM (linha de `crm_conexoes`, sem o token —
/// ele nunca sai do servidor).
class CrmConnection {
  final String id;
  final String provedor;
  final String situacao; // pendente | ativa | erro | desconectada
  final String? ultimoErro;
  final DateTime? ultimaSincronizacao;

  const CrmConnection({
    required this.id,
    required this.provedor,
    required this.situacao,
    this.ultimoErro,
    this.ultimaSincronizacao,
  });

  factory CrmConnection.fromJson(Map<String, dynamic> json) => CrmConnection(
        id: json['id'] as String,
        provedor: json['provedor'] as String,
        situacao: json['situacao'] as String,
        ultimoErro: json['ultimo_erro'] as String?,
        ultimaSincronizacao: json['ultima_sincronizacao'] == null
            ? null
            : DateTime.parse(json['ultima_sincronizacao'] as String).toLocal(),
      );

  /// Uma falha transitória durante a carga inicial deixa a conexão em
  /// 'pendente' com `ultimo_erro` preenchido — isso é erro, não "importando"
  /// (senão a tela ficaria esperando pra sempre).
  CrmConnectionStatus get status {
    if (situacao == 'erro' || ultimoErro != null) {
      return CrmConnectionStatus.erro;
    }
    return situacao == 'pendente'
        ? CrmConnectionStatus.importando
        : CrmConnectionStatus.conectado;
  }
}

/// Resumo da última sincronização (linha de `sincronizacoes`).
class SyncLog {
  final String tipo; // carga_inicial | incremental
  final String situacao; // em_andamento | concluida | erro
  final int lidas;
  final int novas;
  final int atualizadas;
  final int falhas;
  final String? erro;
  final DateTime iniciadaEm;

  /// Progresso da carga inicial: quantas empresas já foram processadas e
  /// quantas se espera processar (nulo = o servidor não conseguiu estimar).
  final int processadas;
  final int? estimado;

  const SyncLog({
    required this.tipo,
    required this.situacao,
    required this.lidas,
    required this.novas,
    required this.atualizadas,
    required this.falhas,
    required this.iniciadaEm,
    this.erro,
    this.processadas = 0,
    this.estimado,
  });

  bool get emAndamento => situacao == 'em_andamento';

  /// 0.0–1.0, ou nulo se não há estimativa (barra indeterminada).
  double? get progresso {
    final total = estimado;
    if (total == null || total <= 0) return null;
    return (processadas / total).clamp(0.0, 1.0);
  }

  /// Tempo restante estimado pelo ritmo da própria carga; nulo enquanto não há
  /// dados suficientes pra projetar.
  Duration? tempoRestante(DateTime agora) {
    final total = estimado;
    if (total == null || processadas < 5 || processadas >= total) return null;
    final decorrido = agora.difference(iniciadaEm);
    if (decorrido.inSeconds < 5) return null;
    final porEmpresa = decorrido.inMilliseconds / processadas;
    return Duration(milliseconds: (porEmpresa * (total - processadas)).round());
  }

  factory SyncLog.fromJson(Map<String, dynamic> json) => SyncLog(
        tipo: json['tipo'] as String,
        situacao: json['situacao'] as String,
        lidas: json['total_lidas'] as int? ?? 0,
        novas: json['total_novas'] as int? ?? 0,
        atualizadas: json['total_atualizadas'] as int? ?? 0,
        falhas: json['total_falhas'] as int? ?? 0,
        erro: json['erro'] as String?,
        iniciadaEm: DateTime.parse(json['iniciada_em'] as String).toLocal(),
        processadas: json['total_processadas'] as int? ?? 0,
        estimado: json['total_estimado'] as int?,
      );
}
