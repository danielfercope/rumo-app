import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/core/app_config.dart';
import 'package:rumo_app/features/company/constants.dart';

void main() {
  test('AppConfig usa o backend local como padrão', () {
    expect(AppConfig.apiBaseUrl, 'http://localhost:8080');
  });

  test('constantes de cadastro estão preenchidas e sem duplicatas', () {
    for (final list in [
      kDepartamentos,
      kRegimesTributarios,
      kProcuracoes,
      kValoresDivida,
      kAnalises,
    ]) {
      expect(list, isNotEmpty);
      expect(list.toSet().length, list.length);
    }
    expect(kPrioridades, isNotEmpty);
    expect(kSetores, isNotEmpty);
    // Os rótulos precisam ser únicos: a tela resolve a chave pelo rótulo.
    expect(kPrioridades.values.toSet().length, kPrioridades.length);
    expect(kSetores.values.toSet().length, kSetores.length);
  });
}
