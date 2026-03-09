import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final locationProvider = FutureProvider<Position?>((ref) async {
  // Localização de Jaraguá do Sul para TESTE
  final jaraguaPosition = Position(
    latitude: -26.4843,
    longitude: -49.0717,
    timestamp: DateTime.now(),
    accuracy: 0.0,
    altitude: 0.0,
    heading: 0.0,
    speed: 0.0,
    speedAccuracy: 0.0,
    altitudeAccuracy: 0.0,
    headingAccuracy: 0.0,
  );

  print('DEBUG: [Location] Forçando localização para Jaraguá do Sul para testes.');
  return jaraguaPosition;
  
  /* Comentado temporariamente para não pegar a localização do simulador (EUA)
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return jaraguaPosition;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return jaraguaPosition;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
      timeLimit: const Duration(seconds: 3),
    ).catchError((e) => jaraguaPosition);
  } catch (e) {
    return jaraguaPosition;
  }
  */
});
