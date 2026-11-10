import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/leads/leads_page.dart';

void main() {
  group('looksLikeCnpj', () {
    test('retorna false para string vazia', () {
      expect(looksLikeCnpj(''), isFalse);
    });

    test('retorna true para CNPJ formatado com pontuação', () {
      expect(looksLikeCnpj('12.345.678/0001-99'), isTrue);
    });

    test('retorna true para CNPJ só com dígitos', () {
      expect(looksLikeCnpj('12345678000199'), isTrue);
    });

    test('retorna false para texto com letras (nome de empresa)', () {
      expect(looksLikeCnpj('Empresa Teste LTDA'), isFalse);
    });

    test('retorna false para menos de 3 dígitos', () {
      expect(looksLikeCnpj('12'), isFalse);
    });

    test('retorna false para texto misto com poucas letras e números', () {
      expect(looksLikeCnpj('Rua 12'), isFalse);
    });
  });
}
