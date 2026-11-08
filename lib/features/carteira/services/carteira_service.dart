import '../../../core/services/api_client.dart';
import '../models/crm_models.dart';

/// Conexão da organização com o CRM dela. Validar, prévia, conectar,
/// sincronizar e desconectar passam pelo Backend (que confere se quem chama é
/// admin e guarda o token cifrado); o status é lido direto do PostgREST.
class CarteiraService {
  final ApiClient _apiClient;

  CarteiraService(this._apiClient);

  // `select=*` NÃO funciona em crm_conexoes: o GRANT por coluna esconde o token
  // e o PostgREST negaria o `*` inteiro. Por isso as colunas são explícitas.
  static const _conexaoColumns =
      'id,group_id,provedor,mapeamento,situacao,ultimo_erro,ultima_sincronizacao';

  Future<List<CrmProperty>> validar(String groupId, String token) async {
    final data = await _apiClient.backendRequest(
      'POST',
      'carteira/conexao/validar',
      body: {'group_id': groupId, 'provedor': 'hubspot', 'token': token},
    ) as Map<String, dynamic>;
    return (data['propriedades'] as List)
        .map((e) => CrmProperty.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CrmPreview> previa(
      String groupId, String token, CrmMapping mapping) async {
    final data = await _apiClient.backendRequest(
      'POST',
      'carteira/conexao/previa',
      body: _credencial(groupId, token, mapping),
    ) as Map<String, dynamic>;
    return CrmPreview.fromJson(data);
  }

  /// Grava a conexão e dispara a carga inicial em segundo plano no servidor.
  Future<void> conectar(String groupId, String token, CrmMapping mapping) =>
      _apiClient.backendRequest(
        'PUT',
        'carteira/conexao',
        body: _credencial(groupId, token, mapping),
      );

  Future<void> sincronizarAgora(String groupId) => _apiClient.backendRequest(
        'POST',
        'carteira/conexao/sincronizar',
        query: {'group_id': groupId},
      );

  Future<void> desconectar(String groupId, {bool apagarCarteira = false}) =>
      _apiClient.backendRequest(
        'DELETE',
        'carteira/conexao',
        query: {
          'group_id': groupId,
          'apagar_carteira': apagarCarteira.toString(),
        },
      );

  Future<CrmConnection?> buscarConexao(String groupId) async {
    final rows = await _apiClient.get('crm_conexoes', query: {
      'group_id': 'eq.$groupId',
      'select': _conexaoColumns,
    }) as List;
    if (rows.isEmpty) return null;
    return CrmConnection.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<SyncLog?> ultimaSincronizacao(String groupId) async {
    final rows = await _apiClient.get('sincronizacoes', query: {
      'group_id': 'eq.$groupId',
      'order': 'iniciada_em.desc',
      'limit': '1',
    }) as List;
    if (rows.isEmpty) return null;
    return SyncLog.fromJson(rows.first as Map<String, dynamic>);
  }

  Map<String, dynamic> _credencial(
          String groupId, String token, CrmMapping mapping) =>
      {
        'group_id': groupId,
        'provedor': 'hubspot',
        'token': token,
        'mapeamento': mapping.toJson(),
      };
}
