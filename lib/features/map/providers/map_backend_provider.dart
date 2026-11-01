import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_config.dart';
import 'google_maps_status_stub.dart'
    if (dart.library.js_interop) 'google_maps_status_web.dart';

/// `true` = Google Maps; `false` = fallback pro OpenStreetMap.
///
/// Cai pro OSM quando não há chave (`GOOGLE_API_KEY` fora do Web, ou
/// `web/env.js` vazio no Web) e, no Web, também quando o Google reporta falha
/// de autenticação depois do boot. No Android/iOS o plugin não avisa quando a
/// chave é rejeitada, então lá só a ausência da chave é detectada.
class UseGoogleMapsNotifier extends Notifier<bool> {
  @override
  bool build() {
    if (!kIsWeb) return AppConfig.googleApiKey.isNotEmpty;
    if (!googleMapsWebAvailable()) return false;
    ref.onDispose(listenGoogleMapsWebFailure(() => state = false));
    return true;
  }
}

final useGoogleMapsProvider =
    NotifierProvider<UseGoogleMapsNotifier, bool>(UseGoogleMapsNotifier.new);
