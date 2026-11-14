import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/company/crm_service.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockApiClient;
  late CrmService service;

  setUp(() {
    mockApiClient = MockApiClient();
    service = CrmService(mockApiClient, activeGroupId: () => 'g1');
  });

  group('getNotesWithOwners', () {
    test('converte a resposta do backend em uma lista de CrmNote', () async {
      when(() => mockApiClient.backend('crm', any())).thenAnswer(
        (_) async => {
          'notes': [
            {
              'id': 'note-1',
              'body': 'Ligação realizada',
              'timestamp': '2026-01-15T10:00:00Z',
              'ownerName': 'Fulano',
            }
          ],
        },
      );

      final notes = await service.getNotesWithOwners('12345678000199');

      expect(notes, hasLength(1));
      expect(notes.first.id, 'note-1');
      expect(notes.first.body, 'Ligação realizada');
      expect(notes.first.ownerName, 'Fulano');
    });

    test('retorna lista vazia quando a resposta não tem notas', () async {
      when(() => mockApiClient.backend('crm', any()))
          .thenAnswer((_) async => {'notes': null});

      final notes = await service.getNotesWithOwners('12345678000199');

      expect(notes, isEmpty);
    });
  });

  group('getContacts', () {
    test('converte a resposta do backend em uma lista de CrmContact', () async {
      when(() => mockApiClient.backend('crm', any())).thenAnswer(
        (_) async => {
          'contacts': [
            {
              'id': 'contact-1',
              'nome': 'Maria',
              'telefone': '47999999999',
              'email': 'maria@empresa.com',
            }
          ],
        },
      );

      final contacts = await service.getContacts('12345678000199');

      expect(contacts, hasLength(1));
      expect(contacts.first.nome, 'Maria');
      expect(contacts.first.email, 'maria@empresa.com');
    });

    test('retorna lista vazia quando a resposta não tem contatos', () async {
      when(() => mockApiClient.backend('crm', any()))
          .thenAnswer((_) async => {'contacts': null});

      final contacts = await service.getContacts('12345678000199');

      expect(contacts, isEmpty);
    });
  });

  group('addNoteToCompany', () {
    test('chama o backend com a action e os dados corretos', () async {
      when(() => mockApiClient.backend('crm', any()))
          .thenAnswer((_) async => {});

      await service.addNoteToCompany(
          cnpj: '12345678000199', noteText: 'Cliente interessado');

      final captured = verify(() => mockApiClient.backend(
            'crm',
            captureAny(),
          )).captured;

      expect(captured.single, {
        'group_id': 'g1',
        'action': 'addNote',
        'cnpj': '12345678000199',
        'noteText': 'Cliente interessado',
      });
    });
  });

  group('addContactToCompany', () {
    test('omite o campo email quando não informado', () async {
      when(() => mockApiClient.backend('crm', any()))
          .thenAnswer((_) async => {});

      await service.addContactToCompany(
        cnpj: '12345678000199',
        nome: 'João',
        telefone: '47988887777',
      );

      final captured = verify(() => mockApiClient.backend(
            'crm',
            captureAny(),
          )).captured;

      expect(captured.single, {
        'group_id': 'g1',
        'action': 'addContact',
        'cnpj': '12345678000199',
        'nome': 'João',
        'telefone': '47988887777',
      });
    });

    test('inclui o campo email quando informado', () async {
      when(() => mockApiClient.backend('crm', any()))
          .thenAnswer((_) async => {});

      await service.addContactToCompany(
        cnpj: '12345678000199',
        nome: 'João',
        telefone: '47988887777',
        email: 'joao@empresa.com',
      );

      final captured = verify(() => mockApiClient.backend(
            'crm',
            captureAny(),
          )).captured;

      expect(captured.single, {
        'group_id': 'g1',
        'action': 'addContact',
        'cnpj': '12345678000199',
        'nome': 'João',
        'telefone': '47988887777',
        'email': 'joao@empresa.com',
      });
    });
  });

  group('organização ativa', () {
    test('leituras também levam o group_id (o servidor confere a pertinência)',
        () async {
      when(() => mockApiClient.backend('crm', any()))
          .thenAnswer((_) async => {'notes': [], 'contacts': []});

      await service.getNotesWithOwners('12345678000199');
      await service.getContacts('12345678000199');

      final bodies = verify(() => mockApiClient.backend('crm', captureAny()))
          .captured
          .cast<Map>();
      expect(bodies.map((b) => b['group_id']), ['g1', 'g1']);
    });

    test('lê a organização a cada chamada: trocar de organização vale na hora',
        () async {
      var ativa = 'g1';
      final s = CrmService(mockApiClient, activeGroupId: () => ativa);
      when(() => mockApiClient.backend('crm', any()))
          .thenAnswer((_) async => {'notes': []});

      await s.getNotesWithOwners('1');
      ativa = 'g2';
      await s.getNotesWithOwners('1');

      final bodies = verify(() => mockApiClient.backend('crm', captureAny()))
          .captured
          .cast<Map>();
      expect(bodies.map((b) => b['group_id']), ['g1', 'g2']);
    });

    test('sem organização ativa não chama o servidor', () async {
      final s = CrmService(mockApiClient, activeGroupId: () => null);

      expect(() => s.getNotesWithOwners('1'), throwsA(isA<StateError>()));
      expect(() => s.getContacts('1'), throwsA(isA<StateError>()));
      expect(() => s.addNoteToCompany(cnpj: '1', noteText: 'x'),
          throwsA(isA<StateError>()));
      expect(() => s.addContactToCompany(cnpj: '1', nome: 'a', telefone: '1'),
          throwsA(isA<StateError>()));
      verifyNever(() => mockApiClient.backend(any(), any()));
    });
  });
}
