import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/core/services/client_error_reporter.dart';

class MockHttpClient extends Mock implements http.Client {}

void main() {
  late MockHttpClient mockClient;
  late List<Map<String, dynamic>> sent;
  late List<Map<String, String>> sentHeaders;

  setUpAll(() => registerFallbackValue(Uri.parse('http://localhost')));

  ApiClient apiWith({Future<String> Function()? token}) => ApiClient(
        baseUrl: 'http://localhost:8080',
        httpClient: mockClient,
        accessTokenProvider: token,
      );

  setUp(() {
    mockClient = MockHttpClient();
    sent = [];
    sentHeaders = [];
    when(() => mockClient.post(any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'))).thenAnswer((inv) async {
      expect(inv.positionalArguments.first.toString(),
          'http://localhost:8080/backend/client-errors');
      sent.add(json.decode(inv.namedArguments[#body] as String)
          as Map<String, dynamic>);
      sentHeaders
          .add(Map<String, String>.from(inv.namedArguments[#headers] as Map));
      return http.Response('', 204);
    });
  });

  test('manda mensagem, pilha, fatal, plataforma e o token quando há login',
      () async {
    final reporter = ClientErrorReporter(
      apiWith(token: () async => 'tok'),
      currentUrl: () => '/radar',
    );

    await reporter.report(StateError('boom'), StackTrace.current, fatal: true);

    expect(sent.single['message'], 'Bad state: boom');
    expect(sent.single['stack'], isNotEmpty);
    expect(sent.single['fatal'], true);
    expect(sent.single['platform'], 'web');
    expect(sent.single['url'], '/radar');
    expect(sentHeaders.single['Authorization'], 'Bearer tok');
  });

  test('sem login o relato vai anônimo e nada é lançado', () async {
    final reporter = ClientErrorReporter(
      apiWith(token: () async => throw ApiException('sem login')),
    );

    await reporter.report('erro', null);

    expect(sent, hasLength(1));
    expect(sentHeaders.single.containsKey('Authorization'), isFalse);
  });

  test('falha de rede não lança', () async {
    when(() => mockClient.post(any(),
        headers: any(named: 'headers'),
        body: any(named: 'body'))).thenThrow(http.ClientException('offline'));
    final reporter = ClientErrorReporter(apiWith(token: () async => 't'));

    await expectLater(reporter.report('erro', null), completes);
  });

  test('ignora o mesmo erro seguido e respeita o teto por sessão', () async {
    final reporter =
        ClientErrorReporter(apiWith(token: () async => 't'), maxReports: 3);

    await reporter.report('a', null);
    await reporter.report('a', null); // repetido
    await reporter.report('b', null);
    await reporter.report('c', null);
    await reporter.report('d', null); // passou do teto

    expect(sent.map((r) => r['message']), ['a', 'b', 'c']);
  });

  test('corta mensagem e pilha nos limites do Backend', () async {
    final reporter = ClientErrorReporter(apiWith(token: () async => 't'));

    await reporter.report('x' * 5000, StackTrace.fromString('y' * 20000));

    expect((sent.single['message'] as String).length, 2000);
    expect((sent.single['stack'] as String).length, 8000);
  });
}
