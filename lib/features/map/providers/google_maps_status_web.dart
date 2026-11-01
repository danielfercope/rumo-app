import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const _failureEvent = 'gmaps-auth-failure';

/// `web/index.html` marca `window.__gmapsFailed` quando não há chave, quando o
/// script não carrega, ou quando o Google chama `gm_authFailure` (chave
/// inválida, cota estourada, domínio não autorizado).
bool googleMapsWebAvailable() {
  final failed = globalContext.getProperty<JSAny?>('__gmapsFailed'.toJS);
  final google = globalContext.getProperty<JSAny?>('google'.toJS);
  return failed.dartify() != true && google != null;
}

/// Chama [onFailure] quando o Google avisa (depois do boot) que a chave não
/// serve. Devolve a função que remove o listener.
void Function() listenGoogleMapsWebFailure(void Function() onFailure) {
  final handler = ((JSAny _) => onFailure()).toJS;
  globalContext.callMethod<JSAny?>(
      'addEventListener'.toJS, _failureEvent.toJS, handler);
  return () => globalContext.callMethod<JSAny?>(
      'removeEventListener'.toJS, _failureEvent.toJS, handler);
}
