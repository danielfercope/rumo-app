import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/auth/providers/profile_provider.dart';
import 'package:rumo_app/features/map/services/tracking_service.dart';

class MockApiClient extends Mock implements ApiClient {}

class _FakeGeolocator extends GeolocatorPlatform {
  bool fail = false;
  int calls = 0;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    calls++;
    if (fail) return Future.error(Exception('sem gps'));
    return Future.value(Position(
      latitude: -26.5,
      longitude: -49.1,
      timestamp: DateTime(2026),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    ));
  }
}

const _profile = UserProfile(
  id: 'uid-1',
  email: 'a@b.com',
  nome: 'Ana',
  departamento: 'Gestão',
  nivelAcesso: 'user',
);

void main() {
  late MockApiClient api;
  late _FakeGeolocator geo;
  late TrackingService service;

  setUp(() {
    api = MockApiClient();
    geo = _FakeGeolocator();
    GeolocatorPlatform.instance = geo;
    service = TrackingService(api);
    when(() => api.upsert(any(), any(), onConflict: any(named: 'onConflict')))
        .thenAnswer((_) async => null);
    when(() => api.post(any(), any())).thenAnswer((_) async => null);
  });

  tearDown(() => service.stop());

  test('startForUser grava a posição atual e o histórico imediatamente',
      () async {
    service.startForUser(_profile);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final upsert = verify(() => api.upsert('tracking_equipe', captureAny(),
        onConflict: 'user_id')).captured.single as Map<String, dynamic>;
    expect(upsert['user_id'], 'uid-1');
    expect(upsert['nome'], 'Ana');
    expect(upsert['latitude'], -26.5);

    final history = verify(() => api.post('tracking_history', captureAny()))
        .captured
        .single as Map<String, dynamic>;
    expect(history['longitude'], -49.1);
  });

  test('chamar startForUser duas vezes não duplica o rastreamento', () async {
    service.startForUser(_profile);
    service.startForUser(_profile);
    await Future<void>.delayed(Duration.zero);
    expect(geo.calls, 1);
  });

  test('erro no GPS é engolido e nada é gravado', () async {
    geo.fail = true;
    service.startForUser(_profile);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    verifyNever(() => api.post(any(), any()));
  });

  test('repete a gravação a cada 5 minutos e para após stop()', () {
    fakeAsync((async) {
      service.startForUser(_profile);
      async.flushMicrotasks();
      expect(geo.calls, 1);

      async.elapse(const Duration(minutes: 5));
      async.flushMicrotasks();
      expect(geo.calls, 2);

      service.stop();
      async.elapse(const Duration(minutes: 10));
      async.flushMicrotasks();
      expect(geo.calls, 2);
    });
  });

  test('após stop() é possível iniciar de novo', () async {
    service.startForUser(_profile);
    service.stop();
    service.startForUser(_profile);
    await Future<void>.delayed(Duration.zero);
    expect(geo.calls, 2);
  });

  test('trackingServiceProvider cria o serviço e para ao descartar', () {
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
    ]);
    final s = container.read(trackingServiceProvider);
    expect(s, isA<TrackingService>());
    container.dispose();
  });
}
