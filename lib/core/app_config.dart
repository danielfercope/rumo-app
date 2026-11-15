import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  static const serverWebClientId =
      String.fromEnvironment('SERVER_WEB_CLIENT_ID');
  static const clientId = String.fromEnvironment('CLIENT_ID');
  static const googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');

  // Backend (PostgREST + serviço Python) atrás do Caddy. Em produção o build
  // passa API_BASE_URL (deploy_frontend.sh). Localmente ela pode ficar vazia:
  // `make run` descobre o IP da máquina pra celular/emulador, e no Web o padrão
  // é o host que serviu a página na porta do Caddy (8080) — nada de IP fixo no .env.
  static const _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
    if (kIsWeb && Uri.base.host.isNotEmpty) {
      return 'http://${Uri.base.host}:8080';
    }
    return 'http://localhost:8080';
  }
}
