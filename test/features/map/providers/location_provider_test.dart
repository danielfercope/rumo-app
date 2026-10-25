import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:rumo_app/features/map/providers/location_provider.dart';

class _FakeGeolocator extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.always;
  LocationPermission afterRequest = LocationPermission.always;
  Position? position;
  Object? positionError;
  Future<Position> Function()? positionBuilder;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => afterRequest;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    if (positionBuilder != null) return positionBuilder!();
    if (positionError != null) return Future.error(positionError!);
    return Future.value(position);
  }
}

Position _pos(double lat, double lon) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime(2026),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

void main() {
  late _FakeGeolocator geo;
  late ProviderContainer container;

  setUp(() {
    geo = _FakeGeolocator()..position = _pos(-10, -20);
    GeolocatorPlatform.instance = geo;
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  Future<Position> read() => container.read(locationProvider.future);

  void expectFallback(Position p) {
    expect(p.latitude, -26.4843);
    expect(p.longitude, -49.0717);
  }

  test('usa a posição do GPS quando tudo está liberado', () async {
    final p = await read();
    expect(p.latitude, -10);
    expect(p.longitude, -20);
  });

  test('usa o fallback quando o serviço de localização está desligado',
      () async {
    geo.serviceEnabled = false;
    expectFallback(await read());
  });

  test('pede permissão quando negada e usa o GPS se concedida', () async {
    geo.permission = LocationPermission.denied;
    geo.afterRequest = LocationPermission.whileInUse;
    final p = await read();
    expect(p.latitude, -10);
  });

  test('usa o fallback quando a permissão continua negada', () async {
    geo.permission = LocationPermission.denied;
    geo.afterRequest = LocationPermission.denied;
    expectFallback(await read());
  });

  test('usa o fallback quando a permissão é negada para sempre', () async {
    geo.permission = LocationPermission.deniedForever;
    expectFallback(await read());
  });

  test('usa o fallback quando o GPS lança erro', () async {
    geo.positionError = Exception('falhou');
    expectFallback(await read());
  });
}
