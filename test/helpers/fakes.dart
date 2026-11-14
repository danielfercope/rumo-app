import 'package:rumo_app/features/map/data/company_repository.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';

Company buildCompany({
  String id = '1',
  String? name = 'Empresa Teste LTDA',
  String? fantasyName = 'Teste',
  String? segment = 'Varejo',
  bool? isClient = false,
  double? latitude = -26.48,
  double? longitude = -49.07,
  String? cnpj = '12345678000199',
}) =>
    Company(
      id: id,
      name: name,
      fantasyName: fantasyName,
      segment: segment,
      isClient: isClient,
      latitude: latitude,
      longitude: longitude,
      cnpj: cnpj,
      address: 'Rua A, 10',
      telefone: '47999999999',
      email: 'contato@teste.com',
      porte: 'ME',
      faturamento: '1234567,89',
      funcionarios: '10-20',
      situacao: 'Ativa',
      dataAbertura: '2010-01-01',
      naturezaJuridica: 'LTDA',
      cnaePrincipal: '4712-1/00',
      dividaAtiva: 'Não',
      saudeTributaria: 'Boa',
      scorePropensao: 'Alto',
      produto: 'Produto X',
      distance: 1.5,
    );

/// Repositório em memória pra testes de widget/provider.
class FakeCompanyRepository implements ICompanyRepository {
  FakeCompanyRepository({
    this.companies = const [],
    this.options = const {},
    this.error,
  });

  List<Company> companies;
  Map<String, dynamic> options;
  Object? error;

  MapFilters? lastFilters;
  String? lastQuery;
  bool? lastIsCnpj;
  double? lastLat;
  String? lastGroupId;

  @override
  Future<List<Company>> getCompanies({
    required double userLat,
    required double userLong,
    MapFilters? filters,
    String? groupId,
  }) async {
    if (error != null) throw error!;
    lastLat = userLat;
    lastGroupId = groupId;
    lastFilters = filters;
    return companies;
  }

  @override
  Future<List<Company>> searchByText({
    required String query,
    required bool isCnpj,
    MapFilters? filters,
    int limit = 200,
    String? groupId,
  }) async {
    if (error != null) throw error!;
    lastGroupId = groupId;
    lastQuery = query;
    lastIsCnpj = isCnpj;
    lastFilters = filters;
    return companies;
  }

  int optionsCalls = 0;

  @override
  Future<Map<String, dynamic>> getFilterOptions() async {
    optionsCalls++;
    if (error != null) throw error!;
    return options;
  }
}
