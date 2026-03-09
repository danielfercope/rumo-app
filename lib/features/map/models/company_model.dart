class Company {
  final String id;
  final String? name;
  final String? fantasyName;
  final String? segment;
  final String? address;
  final double? latitude;
  final double? longitude;
  final bool? isClient;
  
  // Novos campos para o modal detalhado
  final String? cnpj;
  final String? cnaePrincipal;
  final String? telefone;
  final String? email;
  final String? porte;
  final String? faturamento;
  final String? funcionarios;
  final String? situacao;
  final String? dataAbertura;
  final String? naturezaJuridica;
  final String? dividaAtiva;
  final String? saudeTributaria;
  final String? scorePropensao;
  final String? produto;
  
  // Campo calculado localmente
  double? distance;

  Company({
    required this.id,
    this.name,
    this.fantasyName,
    this.segment,
    this.address,
    this.latitude,
    this.longitude,
    this.isClient,
    this.cnpj,
    this.cnaePrincipal,
    this.telefone,
    this.email,
    this.porte,
    this.faturamento,
    this.funcionarios,
    this.situacao,
    this.dataAbertura,
    this.naturezaJuridica,
    this.dividaAtiva,
    this.saudeTributaria,
    this.scorePropensao,
    this.produto,
    this.distance,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    double? parseCoordinate(dynamic value) {
      if (value == null) return null;
      final stringValue = value.toString().trim().replaceAll(',', '.');
      return double.tryParse(stringValue);
    }

    return Company(
      id: json['id'] as String,
      name: json['nome_da_empresa'] as String?,
      fantasyName: json['nome_fantasia'] as String?,
      segment: json['segmento'] as String?,
      address: json['endereco_completo'] as String?,
      latitude: parseCoordinate(json['latitude']),
      longitude: parseCoordinate(json['longitude']),
      isClient: json['cliente'] as bool?,
      cnpj: json['cnpj'] as String?,
      cnaePrincipal: json['cnae_principal'] as String?,
      telefone: json['telefone_principal'] as String?,
      email: json['email_principal'] as String?,
      porte: json['porte_da_empresa'] as String?,
      faturamento: json['faixa_de_faturamento'] as String?,
      funcionarios: json['faixa_de_funcionarios'] as String?,
      situacao: json['situacao'] as String?,
      dataAbertura: json['data_de_abertura']?.toString(),
      naturezaJuridica: json['natureza_juridica'] as String?,
      dividaAtiva: json['divida_ativa_da_uniao'] as String?,
      saudeTributaria: json['saude_tributaria'] as String?,
      scorePropensao: json['score_propensao'] as String?,
      produto: json['produto'] as String?,
    );
  }
}
