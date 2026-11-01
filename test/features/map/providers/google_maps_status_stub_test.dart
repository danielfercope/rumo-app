import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/map/providers/google_maps_status_stub.dart';

void main() {
  // O stub é o que roda fora do Web: não há script do Google pra checar.
  test('fora do Web o Google Maps é considerado disponível', () {
    expect(googleMapsWebAvailable(), isTrue);
  });

  test('o listener de falha é um no-op e nunca dispara o callback', () {
    var fired = false;
    final cancel = listenGoogleMapsWebFailure(() => fired = true);
    cancel();
    expect(fired, isFalse);
  });
}
