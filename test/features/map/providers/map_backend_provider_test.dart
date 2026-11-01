import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/core/app_config.dart';
import 'package:rumo_app/features/map/providers/map_backend_provider.dart';

void main() {
  test('usa Google Maps só quando há GOOGLE_API_KEY (fora do Web)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(useGoogleMapsProvider),
        AppConfig.googleApiKey.isNotEmpty);
  });
}
