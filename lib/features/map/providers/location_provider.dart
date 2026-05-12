import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

// Posição padrão usada como fallback quando o GPS não está disponível
// (ex: simulador sem localização configurada)
const _defaultLat = -26.4843;
const _defaultLon = -49.0717;

Future<Position> _requestPosition() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('GPS: serviço desabilitado — usando posição padrão');
      return _fallback();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('GPS: permissão negada — usando posição padrão');
      return _fallback();
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint('GPS: timeout — usando posição padrão');
        return _fallback();
      },
    );

    debugPrint('GPS: ${pos.latitude}, ${pos.longitude}');
    return pos;
  } catch (e) {
    debugPrint('GPS erro: $e — usando posição padrão');
    return _fallback();
  }
}

Position _fallback() => Position(
      latitude: _defaultLat,
      longitude: _defaultLon,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

// Agora retorna Position (nunca null) — se o GPS falhar usa o fallback
final locationProvider = FutureProvider<Position>((ref) => _requestPosition());
