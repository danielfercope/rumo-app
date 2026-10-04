import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/map/presentation/company_details_modal.dart';

void main() {
  group('formatCnpj', () {
    test('formata um CNPJ de 14 dígitos com a máscara padrão', () {
      expect(formatCnpj('12345678000199'), '12.345.678/0001-99');
    });

    test('formata um CNPJ já pontuado, ignorando a pontuação existente', () {
      expect(formatCnpj('12.345.678/0001-99'), '12.345.678/0001-99');
    });

    test('retorna a string original quando não tem 14 dígitos', () {
      expect(formatCnpj('123'), '123');
    });

    test('retorna a string original para entrada vazia', () {
      expect(formatCnpj(''), '');
    });
  });

  group('formatFaturamento', () {
    test('retorna "N/A" para valor nulo', () {
      expect(formatFaturamento(null), 'N/A');
    });

    test('retorna "N/A" para string vazia', () {
      expect(formatFaturamento(''), 'N/A');
    });

    test('adiciona separador de milhar à parte inteira', () {
      expect(formatFaturamento('1234567,89'), '1.234.567,89');
    });

    test('não altera valores sem separador decimal reconhecido', () {
      expect(formatFaturamento('Até 500 mil'), 'Até 500 mil');
    });

    test('não adiciona separador quando a parte inteira tem 3 dígitos ou menos',
        () {
      expect(formatFaturamento('123,45'), '123,45');
    });
  });
}
