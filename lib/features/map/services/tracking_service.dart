import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/profile_provider.dart';

class TrackingService {
  final SupabaseClient _supabase;
  Timer? _timer;
  bool _running = false;

  TrackingService(this._supabase);

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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final now = DateTime.now().toIso8601String();

      await Future.wait([
        _supabase.from('tracking_equipe').upsert(
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
        _supabase.from('tracking_history').insert({
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
  final service = TrackingService(Supabase.instance.client);
  ref.onDispose(service.stop);
  return service;
});
