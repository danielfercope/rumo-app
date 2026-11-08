import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/carteira/models/crm_models.dart';
import 'package:rumo_app/features/carteira/services/carteira_service.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient api;
  late CarteiraService service;

  const mapping = CrmMapping(
    campoCnpj: 'cnpj',
    campoStatus: 'lifecyclestage',
    valoresCliente: ['customer'],
    valoresPerdido: ['other'],
  );

  setUp(() {
    api = MockApiClient();
    service = CarteiraService(api);
  });

  Map<String, dynamic> lastBody(String method, String path) =>
      verify(() => api.backendRequest(method, path,
          body: captureAny(named: 'body'),
          query: any(named: 'query'))).captured.single as Map<String, dynamic>;

  test('validar envia o token e mapeia as propriedades com opções', () async {
    when(() => api.backendRequest('POST', 'carteira/conexao/validar',
        body: any(named: 'body'), query: any(named: 'query'))).thenAnswer(
      (_) async => {
        'propriedades': [
          {'name': 'cnpj', 'label': 'CNPJ', 'type': 'string', 'options': []},
          {
            'name': 'lifecyclestage',
            'label': 'Estágio',
            'type': 'enumeration',
            'options': [
              {'value': 'customer', 'label': 'Cliente'},
              {'value': 'lead'},
            ],
          },
        ],
      },
    );

    final props = await service.validar('g1', 'pat-123');

    expect(props.map((p) => p.name), ['cnpj', 'lifecyclestage']);
    expect(props[1].options.map((o) => o.label), ['Cliente', 'lead']);
    expect(lastBody('POST', 'carteira/conexao/validar'),
        {'group_id': 'g1', 'provedor': 'hubspot', 'token': 'pat-123'});
  });

  test('previa e conectar enviam o mapeamento no formato do Backend', () async {
    when(() => api.backendRequest(any(), any(),
            body: any(named: 'body'), query: any(named: 'query')))
        .thenAnswer((_) async => {
              'total_com_cnpj': 10,
              'validos': 8,
              'cnpj_invalido': 2,
              'por_status': {'cliente': 3, 'lead': 4, 'perdido': 1},
              'truncado': false,
            });

    final preview = await service.previa('g1', 'tok', mapping);
    await service.conectar('g1', 'tok', mapping);

    expect((
      preview.clientes,
      preview.leads,
      preview.perdidos,
      preview.cnpjInvalido
    ), (
      3,
      4,
      1,
      2
    ));
    // [método, caminho, corpo] de cada chamada, em ordem.
    final calls = verify(() => api.backendRequest(captureAny(), captureAny(),
        body: captureAny(named: 'body'), query: any(named: 'query'))).captured;
    expect([calls[0], calls[1]], ['POST', 'carteira/conexao/previa']);
    expect([calls[3], calls[4]], ['PUT', 'carteira/conexao']);
    for (final body in [calls[2], calls[5]]) {
      expect(body['mapeamento'], {
        'campo_cnpj': 'cnpj',
        'campo_status': 'lifecyclestage',
        'status': {
          'cliente': ['customer'],
          'perdido': ['other'],
        },
      });
    }
  });

  test('sincronizarAgora e desconectar usam query string', () async {
    when(() => api.backendRequest(any(), any(),
        body: any(named: 'body'),
        query: any(named: 'query'))).thenAnswer((_) async => null);

    await service.sincronizarAgora('g1');
    await service.desconectar('g1', apagarCarteira: true);

    verify(() => api.backendRequest('POST', 'carteira/conexao/sincronizar',
        body: any(named: 'body'), query: {'group_id': 'g1'})).called(1);
    verify(() => api.backendRequest('DELETE', 'carteira/conexao',
        body: any(named: 'body'),
        query: {'group_id': 'g1', 'apagar_carteira': 'true'})).called(1);
  });

  test('buscarConexao lista as colunas (nunca select=*) e mapeia a linha',
      () async {
    when(() => api.get('crm_conexoes', query: any(named: 'query')))
        .thenAnswer((_) async => [
              {
                'id': 'c1',
                'provedor': 'hubspot',
                'situacao': 'ativa',
                'ultimo_erro': null,
                'ultima_sincronizacao': '2026-11-08T12:00:00+00:00',
              }
            ]);

    final conn = await service.buscarConexao('g1');

    expect(conn!.id, 'c1');
    expect(conn.status, CrmConnectionStatus.conectado);
    final query =
        verify(() => api.get('crm_conexoes', query: captureAny(named: 'query')))
            .captured
            .single as Map;
    expect(query['group_id'], 'eq.g1');
    expect(query['select'], isNot('*'));
    expect(query['select'], isNot(contains('token')));
  });

  test('buscarConexao devolve null quando nunca conectou', () async {
    when(() => api.get('crm_conexoes', query: any(named: 'query')))
        .thenAnswer((_) async => []);

    expect(await service.buscarConexao('g1'), isNull);
  });

  test('ultimaSincronizacao pede a mais recente da organização', () async {
    when(() => api.get('sincronizacoes', query: any(named: 'query')))
        .thenAnswer((_) async => [
              {
                'tipo': 'carga_inicial',
                'situacao': 'concluida',
                'total_lidas': 312,
                'total_novas': 87,
                'total_atualizadas': 0,
                'total_falhas': 2,
                'erro': null,
                'iniciada_em': '2026-11-08T12:00:00+00:00',
              }
            ]);

    final log = await service.ultimaSincronizacao('g1');

    expect((log!.lidas, log.novas, log.falhas), (312, 87, 2));
    final query = verify(
            () => api.get('sincronizacoes', query: captureAny(named: 'query')))
        .captured
        .single as Map;
    expect(query['order'], 'iniciada_em.desc');
    expect(query['limit'], '1');
  });

  group('CrmConnection.status', () {
    CrmConnection conn(String situacao, {String? erro}) => CrmConnection(
        id: 'c', provedor: 'hubspot', situacao: situacao, ultimoErro: erro);

    test('pendente sem erro é importando', () {
      expect(conn('pendente').status, CrmConnectionStatus.importando);
    });

    test('pendente com erro (falha transitória na carga) é erro', () {
      expect(conn('pendente', erro: '429').status, CrmConnectionStatus.erro);
    });

    test('erro e ativa', () {
      expect(conn('erro', erro: 'token').status, CrmConnectionStatus.erro);
      expect(conn('ativa').status, CrmConnectionStatus.conectado);
    });
  });
}
