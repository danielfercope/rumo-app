class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const serverWebClientId = String.fromEnvironment('SERVER_WEB_CLIENT_ID');
  static const clientId = String.fromEnvironment('CLIENT_ID');
  static const googleApiKey = String.fromEnvironment('GOOGLE_API_KEY');
  static const urlWebhookCrm = String.fromEnvironment('URL_WEBHOOK_CRM');
}
