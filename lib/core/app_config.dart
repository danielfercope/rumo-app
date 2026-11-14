class AppConfig {
  static const serverWebClientId =
      String.fromEnvironment('SERVER_WEB_CLIENT_ID');
  static const clientId = String.fromEnvironment('CLIENT_ID');
  static const googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
  static const urlWebhookCrm = String.fromEnvironment('URL_WEBHOOK_CRM');

  /// Organização (UUID do grupo) cujos cadastros de empresa seguem para o webhook
  /// de CRM acima — o CRM do próprio RUMO. Vazio = o webhook não é chamado pra
  /// ninguém: dado de uma organização não pode ir parar no CRM de outra parte.
  static const webhookCrmGroupId =
      String.fromEnvironment('WEBHOOK_CRM_GROUP_ID');

  // Backend novo (PostgREST + serviço Python) atrás do Caddy — local: Caddy em
  // docker-compose.backend.yml (porta 8080); prod: domínio DuckDNS (semana 3).
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
}
