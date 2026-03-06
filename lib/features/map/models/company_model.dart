class Company {
  final String id;
  final String? name;
  final String? fantasyName;
  final String? segment;
  final String? address;
  final double? latitude;
  final double? longitude;
  final bool? isClient;

  Company({
    required this.id,
    this.name,
    this.fantasyName,
    this.segment,
    this.address,
    this.latitude,
    this.longitude,
    this.isClient,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String,
      name: json['nome_da_empresa'] as String?,
      fantasyName: json['nome_fantasia'] as String?,
      segment: json['segmento'] as String?,
      address: json['endereco_completo'] as String?,
      latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
      isClient: json['cliente'] as bool?,
    );
  }
}
