import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/map/models/company_model.dart';

void main() {
  group('Company.fromJson', () {
    test('faz parse de um JSON completo corretamente', () {
      final company = Company.fromJson({
        'id': 'abc-123',
        'nome_da_empresa': 'Empresa Teste LTDA',
        'nome_fantasia': 'Empresa Teste',
        'segmento': 'Varejo',
        'endereco_completo': 'Rua X, 100',
        'latitude': -26.4843,
        'longitude': -49.0717,
        'cliente': true,
        'cnpj': '12345678000199',
        'distance_km': 1.5,
      });

      expect(company.id, 'abc-123');
      expect(company.name, 'Empresa Teste LTDA');
      expect(company.fantasyName, 'Empresa Teste');
      expect(company.segment, 'Varejo');
      expect(company.latitude, -26.4843);
      expect(company.longitude, -49.0717);
      expect(company.isClient, true);
      expect(company.cnpj, '12345678000199');
      expect(company.distance, 1.5);
    });

    test('aceita coordenadas como string com vírgula decimal', () {
      final company = Company.fromJson({
        'id': 'abc-123',
        'latitude': '-26,4843',
        'longitude': '-49,0717',
      });

      expect(company.latitude, -26.4843);
      expect(company.longitude, -49.0717);
    });

    test('aceita coordenadas nulas sem lançar exceção', () {
      final company = Company.fromJson({
        'id': 'abc-123',
        'latitude': null,
        'longitude': null,
      });

      expect(company.latitude, isNull);
      expect(company.longitude, isNull);
    });

    test('aceita coordenada inválida retornando null em vez de lançar', () {
      final company = Company.fromJson({
        'id': 'abc-123',
        'latitude': 'não é um número',
      });

      expect(company.latitude, isNull);
    });

    test('preenche campos opcionais ausentes como null', () {
      final company = Company.fromJson({'id': 'abc-123'});

      expect(company.name, isNull);
      expect(company.segment, isNull);
      expect(company.isClient, isNull);
      expect(company.distance, isNull);
    });

    test('converte distance_km inteiro para double', () {
      final company = Company.fromJson({'id': 'abc-123', 'distance_km': 3});

      expect(company.distance, 3.0);
    });
  });
}
