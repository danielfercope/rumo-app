import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/company/registration_service.dart';

class MockApiClient extends Mock implements ApiClient {}

const _dadosApi = <String, dynamic>{
  'cnpj': '12345678000199',
  'razao': 'Empresa Teste LTDA',
  'fantasia': 'Teste',
  'email': 'a@b.com',
  'site': 'https://teste.com',
  'ddd_1': '47',
  'tel_1': '999999999',
  'log_tipo': 'Rua',
  'log_nome': 'A',
  'log_num': '10',
  'log_bairro': 'Centro',
  'log_municipio': 'Joinville',
  'log_uf': 'SC',
  'log_cep': '89200000',
  'natureza_juridica': 'LTDA',
  'porte': 'ME',
  'situacao_cadastral': 'Ativa',
  'data_abertura': '20100131',
  'cnae_principal': '4712100',
};

void main() {
  late MockApiClient api;
  late RegistrationService service;

  setUp(() {
    api = MockApiClient();
    service = RegistrationService(api);
    when(() => api.upsert(any(), any(), onConflict: any(named: 'onConflict')))
        .thenAnswer((_) async => null);
  });

  Map<String, dynamic> savedBody() => verify(() => api.upsert(
          'companies', captureAny(),
          onConflict: 'cnpj')).captured.single as Map<String, dynamic>;

  group('saveCompany', () {
    test('mapeia os campos da consulta de CNPJ para a tabela companies',
        () async {
      await service.saveCompany(_dadosApi, -26.4, -49.0, 'ROOFTOP');

      final body = savedBody();
      expect(body['cnpj'], '12345678000199');
      expect(body['razao_social'], 'Empresa Teste LTDA');
      expect(body['nome_fantasia'], 'Teste');
      expect(body['telefone_principal'], '47999999999');
      expect(body['endereco_completo'], 'Rua A, 10 - Centro');
      expect(body['data_abertura'], '2010-01-31');
      expect(body['latitude'], -26.4);
      expect(body['longitude'], -49.0);
      expect(body['precisao_geocodificacao'], 'ROOFTOP');
    });

    test('telefone fica nulo sem DDD ou número e data inválida vira nula',
        () async {
      await service.saveCompany(
          {..._dadosApi, 'ddd_1': '', 'data_abertura': '00000000'},
          0,
          0,
          'APPROXIMATE');
      final body = savedBody();
      expect(body['telefone_principal'], isNull);
      expect(body['data_abertura'], isNull);
    });

    test('data curta demais é descartada em vez de lançar erro', () async {
      await service.saveCompany(
          {..._dadosApi, 'data_abertura': '2010'}, 0, 0, 'APPROXIMATE');
      expect(savedBody()['data_abertura'], isNull);
    });

    test('campos ausentes não quebram o endereço', () async {
      await service.saveCompany({'cnpj': '1'}, 0, 0, 'APPROXIMATE');
      final body = savedBody();
      expect(body['endereco_completo'], ' ,  - ');
      expect(body['data_abertura'], isNull);
    });
  });

  group('geocodeAddress', () {
    Future<T> withClient<T>(
        http.Client client, Future<T> Function() body) async {
      return http.runWithClient(body, () => client);
    }

    test('devolve coordenadas e precisão quando o status é OK', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'maps.googleapis.com');
        expect(request.url.queryParameters['address'], 'Rua A, 10');
        return http.Response(
            json.encode({
              'status': 'OK',
              'results': [
                {
                  'geometry': {
                    'location': {'lat': -26.5, 'lng': -49.1},
                    'location_type': 'ROOFTOP',
                  }
                }
              ]
            }),
            200);
      });

      final geo = await withClient(client, () => service.geocodeAddress('Rua A, 10'));
      expect(geo.lat, -26.5);
      expect(geo.lon, -49.1);
      expect(geo.precisao, 'ROOFTOP');
    });

    test('usa APPROXIMATE quando location_type não vem', () async {
      final client = MockClient((_) async => http.Response(
          json.encode({
            'status': 'OK',
            'results': [
              {
                'geometry': {
                  'location': {'lat': 1, 'lng': 2}
                }
              }
            ]
          }),
          200));
      final geo = await withClient(client, () => service.geocodeAddress('x'));
      expect(geo.precisao, 'APPROXIMATE');
      expect(geo.lat, 1.0);
    });

    test('lança mensagem amigável quando o endereço não é encontrado',
        () async {
      final client = MockClient(
          (_) async => http.Response(json.encode({'status': 'ZERO_RESULTS'}), 200));
      expect(
        withClient(client, () => service.geocodeAddress('x')),
        throwsA('Endereço não encontrado. Verifique o CNPJ informado.'),
      );
    });
  });

  group('sendToWebhook', () {
    const form = {
      'primeiro_nome': 'Ana',
      'sobrenome': 'Silva',
      'tipo_lead': 'Novo lead',
    };

    test('envia o payload e retorna true em 2xx', () async {
      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        expect(request.headers['Content-Type'], contains('application/json'));
        payload = json.decode(request.body) as Map<String, dynamic>;
        return http.Response('ok', 200);
      });

      final ok = await http.runWithClient(
          () => service.sendToWebhook(_dadosApi, form, 'u@x.com', 'Usuária'),
          () => client);

      expect(ok, isTrue);
      final assignments = (payload['assignments'] as List).cast<Map>();
      Object? valueOf(String name) =>
          assignments.firstWhere((a) => a['name'] == name)['value'];
      expect(valueOf('Primeiro nome'), 'Ana');
      expect(valueOf('Nome da empresa'), 'Teste');
      expect(valueOf('CNPJ'), '12345678000199');
      expect(valueOf('E-mail de quem está indicando o lead/cliente'), 'u@x.com');
      expect(valueOf('RUMO'), true);
    });

    test('usa a razão social quando não há nome fantasia', () async {
      late Map<String, dynamic> payload;
      final client = MockClient((request) async {
        payload = json.decode(request.body) as Map<String, dynamic>;
        return http.Response('ok', 201);
      });
      await http.runWithClient(
          () => service.sendToWebhook(
              {..._dadosApi, 'fantasia': null}, form, '', ''),
          () => client);
      final nome = (payload['assignments'] as List)
          .cast<Map>()
          .firstWhere((a) => a['name'] == 'Nome da empresa');
      expect(nome['value'], 'Empresa Teste LTDA');
    });

    test('retorna false em resposta não-2xx', () async {
      final client = MockClient((_) async => http.Response('erro', 500));
      final ok = await http.runWithClient(
          () => service.sendToWebhook(_dadosApi, form, '', ''), () => client);
      expect(ok, isFalse);
    });

    test('retorna false quando a requisição falha', () async {
      final client = MockClient((_) async => throw http.ClientException('x'));
      final ok = await http.runWithClient(
          () => service.sendToWebhook(_dadosApi, form, '', ''), () => client);
      expect(ok, isFalse);
    });
  });

  test('registrationServiceProvider usa o ApiClient do provider', () {
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    expect(container.read(registrationServiceProvider),
        isA<RegistrationService>());
  });
}
