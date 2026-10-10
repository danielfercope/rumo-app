class AppConfig {
  // TODO(migração Supabase→PostgREST, semana 4): remover depois do cutover
  // final dos arquivos que ainda chamam Supabase.instance.client diretamente
  // (company_service, tracking_service, registration_service, hubspot_service).
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const serverWebClientId =
      String.fromEnvironment('SERVER_WEB_CLIENT_ID');
  static const clientId = String.fromEnvironment('CLIENT_ID');
  static const googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
  static const urlWebhookCrm = String.fromEnvironment('URL_WEBHOOK_CRM');

  // Backend novo (PostgREST + serviço Python) atrás do Caddy — local: Caddy em
  // docker-compose.backend.yml (porta 8080); prod: domínio DuckDNS (semana 3).
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
}
