import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/company/hubspot_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

void main() {
  late MockSupabaseClient mockClient;
  late MockFunctionsClient mockFunctions;
  late HubSpotService service;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockFunctions = MockFunctionsClient();
    when(() => mockClient.functions).thenReturn(mockFunctions);
    service = HubSpotService(mockClient);
  });

  group('getNotesWithOwners', () {
    test('converte a resposta da edge function em uma lista de HubSpotNote',
        () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(
                status: 200,
                data: {
                  'notes': [
                    {
                      'id': 'note-1',
                      'body': 'Ligação realizada',
                      'timestamp': '2026-01-15T10:00:00Z',
                      'ownerName': 'Fulano',
                    }
                  ],
                },
              ));

      final notes = await service.getNotesWithOwners('12345678000199');

      expect(notes, hasLength(1));
      expect(notes.first.id, 'note-1');
      expect(notes.first.body, 'Ligação realizada');
      expect(notes.first.ownerName, 'Fulano');
    });

    test('retorna lista vazia quando a resposta não tem notas', () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(
                status: 200,
                data: {'notes': null},
              ));

      final notes = await service.getNotesWithOwners('12345678000199');

      expect(notes, isEmpty);
    });
  });

  group('getContacts', () {
    test('converte a resposta da edge function em uma lista de HubSpotContact',
        () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(
                status: 200,
                data: {
                  'contacts': [
                    {
                      'id': 'contact-1',
                      'nome': 'Maria',
                      'telefone': '47999999999',
                      'email': 'maria@empresa.com',
                    }
                  ],
                },
              ));

      final contacts = await service.getContacts('12345678000199');

      expect(contacts, hasLength(1));
      expect(contacts.first.nome, 'Maria');
      expect(contacts.first.email, 'maria@empresa.com');
    });

    test('retorna lista vazia quando a resposta não tem contatos', () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(
                status: 200,
                data: {'contacts': null},
              ));

      final contacts = await service.getContacts('12345678000199');

      expect(contacts, isEmpty);
    });
  });

  group('addNoteToCompany', () {
    test('invoca a edge function hubspot com a action e os dados corretos',
        () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(status: 200, data: {}));

      await service.addNoteToCompany(
          cnpj: '12345678000199', noteText: 'Cliente interessado');

      final captured = verify(() => mockFunctions.invoke(
            'hubspot',
            body: captureAny(named: 'body'),
          )).captured;

      expect(captured.single, {
        'action': 'addNote',
        'cnpj': '12345678000199',
        'noteText': 'Cliente interessado',
      });
    });
  });

  group('addContactToCompany', () {
    test('omite o campo email quando não informado', () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(status: 200, data: {}));

      await service.addContactToCompany(
        cnpj: '12345678000199',
        nome: 'João',
        telefone: '47988887777',
      );

      final captured = verify(() => mockFunctions.invoke(
            'hubspot',
            body: captureAny(named: 'body'),
          )).captured;

      expect(captured.single, {
        'action': 'addContact',
        'cnpj': '12345678000199',
        'nome': 'João',
        'telefone': '47988887777',
      });
    });

    test('inclui o campo email quando informado', () async {
      when(() => mockFunctions.invoke(any(), body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(status: 200, data: {}));

      await service.addContactToCompany(
        cnpj: '12345678000199',
        nome: 'João',
        telefone: '47988887777',
        email: 'joao@empresa.com',
      );

      final captured = verify(() => mockFunctions.invoke(
            'hubspot',
            body: captureAny(named: 'body'),
          )).captured;

      expect(captured.single, {
        'action': 'addContact',
        'cnpj': '12345678000199',
        'nome': 'João',
        'telefone': '47988887777',
        'email': 'joao@empresa.com',
      });
    });
  });
}
