/// Fora do Web não há script do Google Maps pra checar — a disponibilidade
/// depende só da chave (ver `map_backend_provider.dart`).
bool googleMapsWebAvailable() => true;

/// Sem eventos de falha fora do Web; devolve um cancelamento vazio.
void Function() listenGoogleMapsWebFailure(void Function() onFailure) => () {};
