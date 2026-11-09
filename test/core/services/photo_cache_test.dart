import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rumo_app/core/services/photo_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const url = 'https://lh3.googleusercontent.com/a/foto=s96-c';
  final photo = Uint8List.fromList([1, 2, 3, 4]);

  late DateTime now;
  late int requests;
  late int status;
  late Uint8List body;

  PhotoCache cache({Future<SharedPreferences> Function()? prefs}) => PhotoCache(
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes(body, status);
        }),
        prefs: prefs,
        now: () => now,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 9, 12);
    requests = 0;
    status = 200;
    body = photo;
  });

  test('sem URL não vai à rede e devolve null', () async {
    final c = cache();
    expect(await c.load(null), isNull);
    expect(await c.load(''), isNull);
    expect(requests, 0);
  });

  test('baixa uma vez e as chamadas seguintes saem da memória', () async {
    final c = cache();
    expect(await c.load(url), photo);
    expect(await c.load(url), photo);
    expect(await c.load(url), photo);
    expect(requests, 1);
  });

  test('sobrevive a uma recarga: outra instância lê do disco sem rede',
      () async {
    await cache().load(url);
    expect(requests, 1);

    final reloaded = cache(); // memória vazia, como ao recarregar a página
    expect(await reloaded.load(url), photo);
    expect(requests, 1);
  });

  test('pedidos simultâneos (avatar + marcador) dividem uma só ida à rede',
      () async {
    final gate = Completer<void>();
    var calls = 0;
    final c = PhotoCache(
      client: MockClient((_) async {
        calls++;
        await gate.future;
        return http.Response.bytes(photo, 200);
      }),
      now: () => now,
    );

    final both = Future.wait([c.load(url), c.load(url)]);
    gate.complete();

    expect(await both, [photo, photo]);
    expect(calls, 1);
  });

  test('vencida, baixa de novo e guarda a nova', () async {
    final c = cache();
    await c.load(url);
    now = now.add(const Duration(hours: 25));
    body = Uint8List.fromList([9, 9]);

    expect(await c.load(url), [9, 9]);
    expect(requests, 2);
  });

  test('vencida e o Google recusa (429): serve a cópia guardada', () async {
    final c = cache();
    await c.load(url);
    now = now.add(const Duration(hours: 25));
    status = 429;

    expect(await c.load(url), photo);
  });

  test('sem cópia e com falha: null, e não insiste até passar o intervalo',
      () async {
    status = 429;
    final c = cache();

    expect(await c.load(url), isNull);
    expect(await c.load(url), isNull);
    expect(requests, 1, reason: 'insistir a cada carga alimenta o 429');

    now = now.add(const Duration(minutes: 11));
    status = 200;
    expect(await c.load(url), photo);
    expect(requests, 2);
  });

  test('resposta 200 com corpo vazio conta como falha', () async {
    body = Uint8List(0);
    expect(await cache().load(url), isNull);
  });

  test('outra URL não reaproveita a foto da anterior', () async {
    final c = cache();
    await c.load(url);
    body = Uint8List.fromList([7]);

    expect(await c.load('$url-outra'), [7]);
    expect(requests, 2);
  });

  test('sem armazenamento (janela privada) ainda funciona, só em memória',
      () async {
    final c = cache(prefs: () async => throw StateError('bloqueado'));
    expect(await c.load(url), photo);
    expect(await c.load(url), photo);
    expect(requests, 1);
  });

  test('clear esquece a foto, em memória e no disco', () async {
    final c = cache();
    await c.load(url);
    await c.clear();

    expect(await cache().load(url), photo);
    expect(requests, 2); // baixou de novo: nada ficou guardado
  });
}
