import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/api_client.dart';
import '../../auth/providers/profile_provider.dart';

class TrackingService {
  final ApiClient _apiClient;
  Timer? _timer;
  bool _running = false;

  TrackingService(this._apiClient);

  void startForUser(UserProfile profile) {
    if (_running) return;
    _running = true;
    _save(profile);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _save(profile));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> _save(UserProfile profile) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final now = DateTime.now().toIso8601String();

      await Future.wait([
        _apiClient.upsert(
          'tracking_equipe',
          {
            'user_id': profile.id,
            'email': profile.email,
            'nome': profile.nome,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'ultimo_visto': now,
          },
          onConflict: 'user_id',
        ),
        _apiClient.post('tracking_history', {
          'user_id': profile.id,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'captured_at': now,
        }),
      ]);
    } catch (_) {
      // Falha silenciosa — tracking não deve interromper a UI
    }
  }
}

final trackingServiceProvider = Provider<TrackingService>((ref) {
  final service = TrackingService(ref.watch(apiClientProvider));
  ref.onDispose(service.stop);
  return service;
});
