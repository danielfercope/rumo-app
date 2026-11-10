import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockClient;
  late ApiClient apiClient;

  setUpAll(() {
    registerFallbackValue(Uri.parse('http://localhost'));
    registerFallbackValue(http.Request('GET', Uri.parse('http://localhost')));
  });

  setUp(() {
    mockClient = MockHttpClient();
    apiClient = ApiClient(
      baseUrl: 'http://localhost:8080',
      httpClient: mockClient,
      accessTokenProvider: () async => 'token-de-teste',
    );
  });

  group('get', () {
    test('decodifica uma resposta 200 com corpo JSON', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('[{"id":"1"}]', 200));

      final result = await apiClient.get('companies');

      expect(result, [
        {'id': '1'}
      ]);
    });

    test('monta a URL com /rest/<table> e os query params', () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('[]', 200));

      await apiClient.get('profiles', query: {'id': 'eq.123'});

      final captured = verify(() =>
              mockClient.get(captureAny(), headers: any(named: 'headers')))
          .captured;
      final uri = captured.single as Uri;
      expect(uri.toString(), 'http://localhost:8080/rest/profiles?id=eq.123');
    });

    test('lança ApiException com os dados do erro em respostas não-2xx',
        () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(
              jsonEncode(
                  {'code': 'PGRST301', 'message': 'JWSInvalidSignature'}),
              401));

      expect(
        () => apiClient.get('companies'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.code, 'code', 'PGRST301')
            .having((e) => e.message, 'message', 'JWSInvalidSignature')),
      );
    });

    test('lança ApiException genérica quando o corpo do erro não é JSON válido',
        () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('erro interno', 500));

      expect(
        () => apiClient.get('companies'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
      );
    });

    test('envia o token do accessTokenProvider no header Authorization',
        () async {
      when(() => mockClient.get(any(), headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response('[]', 200));

      await apiClient.get('companies');

      final captured = verify(() =>
              mockClient.get(any(), headers: captureAny(named: 'headers')))
          .captured;
      final headers = captured.single as Map<String, String>;
      expect(headers['Authorization'], 'Bearer token-de-teste');
    });
  });

  group('post', () {
    test('retorna null quando o corpo da resposta vem vazio', () async {
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response('', 201));

      final result = await apiClient.post('tracking_history', {'user_id': 'x'});

      expect(result, isNull);
    });
  });

  group('upsert', () {
    test('envia Prefer: merge-duplicates e o query param on_conflict',
        () async {
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response('[]', 200));

      await apiClient.upsert('tracking_equipe', {'user_id': 'x'},
          onConflict: 'user_id');

      final captured = verify(() => mockClient.post(captureAny(),
          headers: captureAny(named: 'headers'),
          body: any(named: 'body'))).captured;
      final uri = captured[0] as Uri;
      final headers = captured[1] as Map<String, String>;

      expect(uri.queryParameters['on_conflict'], 'user_id');
      expect(headers['Prefer'],
          'resolution=merge-duplicates,return=representation');
    });
  });

  group('rpc', () {
    test('monta a URL /rest/rpc/<fn> e envia os parâmetros no corpo', () async {
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response('[]', 200));

      await apiClient.rpc('search_companies', {'p_lat': -26.4});

      final captured = verify(() => mockClient.post(captureAny(),
          headers: any(named: 'headers'),
          body: captureAny(named: 'body'))).captured;
      final uri = captured[0] as Uri;
      final body = captured[1] as String;

      expect(uri.path, '/rest/rpc/search_companies');
      expect(jsonDecode(body), {'p_lat': -26.4});
    });
  });

  group('backend', () {
    test('monta a URL /backend/<path>', () async {
      when(() => mockClient.post(any(),
              headers: any(named: 'headers'), body: any(named: 'body')))
          .thenAnswer((_) async => http.Response('{}', 200));

      await apiClient.backend('crm', {'action': 'addNote'});

      final captured = verify(() => mockClient.post(captureAny(),
          headers: any(named: 'headers'), body: any(named: 'body'))).captured;
      final uri = captured.single as Uri;
      expect(uri.path, '/backend/crm');
    });
  });

  group('backendRequest', () {
    http.StreamedResponse streamed(String body, int status) =>
        http.StreamedResponse(Stream.value(utf8.encode(body)), status);

    test('PUT envia o corpo JSON e o token', () async {
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => streamed('{"situacao":"pendente"}', 202));

      final result = await apiClient
          .backendRequest('PUT', 'carteira/conexao', body: {'group_id': 'g1'});

      expect(result, {'situacao': 'pendente'});
      final request = verify(() => mockClient.send(captureAny()))
          .captured
          .single as http.Request;
      expect(request.method, 'PUT');
      expect(request.url.path, '/backend/carteira/conexao');
      expect(jsonDecode(request.body), {'group_id': 'g1'});
      expect(request.headers['Authorization'], 'Bearer token-de-teste');
    });

    test('DELETE com query string e resposta 204 devolve null', () async {
      when(() => mockClient.send(any()))
          .thenAnswer((_) async => streamed('', 204));

      final result = await apiClient.backendRequest(
          'DELETE', 'carteira/conexao',
          query: {'group_id': 'g1', 'apagar_carteira': 'true'});

      expect(result, isNull);
      final request = verify(() => mockClient.send(captureAny()))
          .captured
          .single as http.Request;
      expect(request.url.queryParameters,
          {'group_id': 'g1', 'apagar_carteira': 'true'});
      expect(request.body, isEmpty);
    });
  });

  group('ApiException.fromResponse', () {
    test('lê "detail" em texto (formato do FastAPI)', () {
      final e = ApiException.fromResponse(
          http.Response(jsonEncode({'detail': 'O CRM recusou o token'}), 400));
      expect(e.message, 'O CRM recusou o token');
      expect(e.statusCode, 400);
    });

    test('junta as mensagens de um "detail" em lista (422)', () {
      final e = ApiException.fromResponse(http.Response(
          jsonEncode({
            'detail': [
              {
                'loc': ['body', 'token'],
                'msg': 'campo obrigatório'
              },
              {
                'loc': ['body', 'group_id'],
                'msg': 'inválido'
              },
            ]
          }),
          422));
      expect(e.message, 'campo obrigatório; inválido');
    });

    test('"message" do PostgREST continua tendo prioridade', () {
      final e = ApiException.fromResponse(http.Response(
          jsonEncode({'message': 'JWSInvalidSignature', 'detail': 'x'}), 401));
      expect(e.message, 'JWSInvalidSignature');
    });
  });
}
