import 'api_client.dart';

/// Relata erros não tratados do app ao Backend (`/backend/client-errors`),
/// onde não há Crashlytics — hoje, o Flutter Web. Android/iOS continuam no
/// Crashlytics (`main.dart`).
///
/// Um erro em loop (ex.: num `build`) dispararia centenas de relatos: o mesmo
/// erro seguido é ignorado e cada sessão manda no máximo [maxReports]. O
/// Backend tem o próprio limite por cliente.
class ClientErrorReporter {
  ClientErrorReporter(
    this._api, {
    this.maxReports = 10,
    this.platform = 'web',
    this.currentUrl,
  });

  final ApiClient _api;
  final int maxReports;
  final String platform;

  /// Rota/URL atual, só pra contexto no log (no Web, `Uri.base`).
  final String Function()? currentUrl;

  static const _maxMessage = 2000;
  static const _maxStack = 8000;
  static const _maxUrl = 500;

  int _sent = 0;
  String? _lastSignature;

  Future<void> report(Object error, StackTrace? stack, {bool fatal = false}) {
    final message = _truncate(error.toString(), _maxMessage);
    final stackText =
        stack == null ? null : _truncate(stack.toString(), _maxStack);
    final signature = '$message|${stackText?.split('\n').first}';
    if (_sent >= maxReports || signature == _lastSignature) {
      return Future.value();
    }
    _lastSignature = signature;
    _sent++;

    String? url;
    try {
      url = currentUrl == null ? null : _truncate(currentUrl!(), _maxUrl);
    } catch (_) {}

    return _api.reportClientError({
      'message': message.isEmpty ? '(erro sem mensagem)' : message,
      if (stackText != null && stackText.isNotEmpty) 'stack': stackText,
      'fatal': fatal,
      'platform': platform,
      if (url != null) 'url': url,
    });
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}
