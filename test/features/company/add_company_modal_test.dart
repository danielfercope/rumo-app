import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/auth/providers/profile_provider.dart';
import 'package:rumo_app/features/company/add_company_modal.dart';
import 'package:rumo_app/features/company/crm_service.dart';
import 'package:rumo_app/features/company/registration_service.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';
import 'package:rumo_app/features/map/providers/location_provider.dart';

class MockRegistrationService extends Mock implements RegistrationService {}

class MockCrmService extends Mock implements CrmService {}

Position _pos() => Position(
      latitude: -26.48,
      longitude: -49.07,
      timestamp: DateTime(2026),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

const _dadosApi = <String, dynamic>{
  'cnpj': '12345678000199',
  'razao': 'Empresa Teste LTDA',
  'fantasia': 'Teste',
  'email': 'a@b.com',
  'ddd_1': '47',
  'tel_1': '999999999',
  'log_tipo': 'Rua',
  'log_nome': 'A',
  'log_num': '10',
  'log_bairro': 'Centro',
  'log_municipio': 'Joinville',
  'log_uf': 'SC',
  '0': {'socios_nome': 'Maria Souza Lima'},
};

final _grupo = MyGroup(
  group: Group(
    id: 'g1',
    name: 'Agro Sul',
    trackingEnabled: false,
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
  ),
  role: 'admin',
  joinedAt: DateTime(2026, 1, 1),
);

void main() {
  late MockRegistrationService service;
  late MockCrmService crm;

  setUp(() {
    service = MockRegistrationService();
    when(() => service.cnpjInPortfolio(any(), any()))
        .thenAnswer((_) async => false);
    when(() => service.fetchCompanyData(any()))
        .thenAnswer((_) async => Map<String, dynamic>.from(_dadosApi));
    when(() => service.geocodeAddress(any())).thenAnswer(
        (_) async => (lat: -26.48, lon: -49.07, precisao: 'ROOFTOP'));
    when(() => service.isWithinProximity(any(), any(), any(), any()))
        .thenReturn(true);
    when(() => service.saveCompany(any(), any(), any(), any(), any()))
        .thenAnswer((_) async => false);
    crm = MockCrmService();
    when(() => crm.addContactToCompany(
          cnpj: any(named: 'cnpj'),
          nome: any(named: 'nome'),
          telefone: any(named: 'telefone'),
          email: any(named: 'email'),
        )).thenAnswer((_) async {});
  });

  /// Abre o modal dentro de uma rota, pra conseguir observar o `pop(true)`.
  Future<List<Object?>> pumpModal(WidgetTester tester,
      {bool withLocation = true, bool withGroup = true}) async {
    tester.view.physicalSize = const Size(2400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final results = <Object?>[];

    final container = ProviderContainer(overrides: [
      registrationServiceProvider.overrideWithValue(service),
      crmServiceProvider.overrideWithValue(crm),
      activeGroupProvider.overrideWithValue(withGroup ? _grupo : null),
      locationProvider.overrideWith((ref) =>
          withLocation ? Future.value(_pos()) : Completer<Position>().future),
      profileProvider.overrideWith((ref) async => const UserProfile(
            id: 'u1',
            email: 'u@x.com',
            nome: 'Usuária',
            departamento: 'Gestão',
            nivelAcesso: 'user',
          )),
    ]);
    addTearDown(container.dispose);
    // Mantém o locationProvider e o profileProvider vivos e resolvidos, como
    // acontece no app (a RadarPage os observa).
    container.listen(locationProvider, (_, __) {});
    container.listen(profileProvider, (_, __) {});

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoButton(
            child: const Text('abrir'),
            onPressed: () async => results.add(await showCupertinoModalPopup(
              context: context,
              builder: (_) => const AddCompanyModal(),
            )),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle(); // resolve location/profile
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return results;
  }

  Future<void> goToStep2(WidgetTester tester) async {
    await tester.enterText(find.byType(CupertinoTextField), '12345678000199');
    await tester.tap(find.text('Validar e Buscar'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSalvar(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Salvar e Enviar para CRM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar e Enviar para CRM'));
    await tester.pumpAndSettle();
  }

  Finder campo(String label) => find
      .descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Column)),
        matching: find.byType(CupertinoTextField),
      )
      .first;

  group('passo 1', () {
    testWidgets('mostra o título e valida o tamanho do CNPJ', (tester) async {
      await pumpModal(tester);
      expect(find.text('Nova Empresa'), findsOneWidget);

      await tester.enterText(find.byType(CupertinoTextField), '123');
      await tester.tap(find.text('Validar e Buscar'));
      await tester.pumpAndSettle();
      expect(find.text('CNPJ deve ter 14 dígitos.'), findsOneWidget);
    });

    testWidgets('o campo só aceita dígitos e até 14 caracteres',
        (tester) async {
      await pumpModal(tester);
      await tester.enterText(
          find.byType(CupertinoTextField), '12.345.678/0001-99999999');
      await tester.pump();
      final field =
          tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
      expect(field.controller!.text, '12345678000199');
    });

    testWidgets('avisa quando a localização não está disponível',
        (tester) async {
      await pumpModal(tester, withLocation: false);
      await goToStep2(tester);
      expect(find.textContaining('Localização não disponível'), findsOneWidget);
    });

    testWidgets('bloqueia CNPJ já cadastrado', (tester) async {
      when(() => service.cnpjInPortfolio(any(), any()))
          .thenAnswer((_) async => true);
      await pumpModal(tester);
      await goToStep2(tester);
      verify(() => service.cnpjInPortfolio('g1', '12345678000199')).called(1);
      expect(find.text('Esta empresa já está na carteira da sua organização.'),
          findsOneWidget);
      expect(find.text('Nova Empresa'), findsOneWidget);
    });

    testWidgets('bloqueia quando a empresa está longe', (tester) async {
      when(() => service.isWithinProximity(any(), any(), any(), any()))
          .thenReturn(false);
      await pumpModal(tester);
      await goToStep2(tester);
      expect(find.textContaining('mais de 2 km'), findsOneWidget);
    });

    testWidgets('mostra o erro quando a consulta falha', (tester) async {
      when(() => service.fetchCompanyData(any()))
          .thenThrow('Falha na consulta');
      await pumpModal(tester);
      await goToStep2(tester);
      expect(find.text('Falha na consulta'), findsOneWidget);
    });

    testWidgets('fechar no cabeçalho descarta o modal', (tester) async {
      final results = await pumpModal(tester);
      await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
      await tester.pumpAndSettle();
      expect(find.text('Nova Empresa'), findsNothing);
      expect(results, [null]);
    });
  });

  group('passo 2', () {
    testWidgets(
        'pede só nome do responsável, telefone e e-mail, já preenchidos',
        (tester) async {
      await pumpModal(tester);
      await goToStep2(tester);

      expect(find.text('Responsável'), findsOneWidget);
      expect(find.text('Teste'), findsOneWidget);
      expect(find.byType(CupertinoTextField), findsNWidgets(3));
      expect(find.text('Maria Souza Lima'), findsOneWidget);
      expect(find.text('47999999999'), findsOneWidget);
      expect(find.text('a@b.com'), findsOneWidget);
      for (final antiga in [
        'Possui débitos?',
        'Regime tributário',
        'Prioridade',
        'Tipo de lead',
        'Setor da empresa',
      ]) {
        expect(find.text(antiga), findsNothing);
      }
    });

    testWidgets('sem sócio nos dados deixa o nome vazio', (tester) async {
      when(() => service.fetchCompanyData(any())).thenAnswer((_) async => {
            'razao': 'Só Razão LTDA',
            'cnpj': '12345678000199',
          });
      await pumpModal(tester);
      await goToStep2(tester);
      expect(find.text('Só Razão LTDA'), findsOneWidget);
      await tapSalvar(tester);
      expect(
          find.text('Preencha: Nome completo do responsável, Telefone, E-mail'),
          findsOneWidget);
      verifyNever(() => service.saveCompany(any(), any(), any(), any(), any()));
    });

    testWidgets('recusa e-mail inválido', (tester) async {
      await pumpModal(tester);
      await goToStep2(tester);
      await tester.enterText(campo('E-mail'), 'sem-arroba');
      await tapSalvar(tester);
      expect(find.text('E-mail inválido.'), findsOneWidget);
      verifyNever(() => service.saveCompany(any(), any(), any(), any(), any()));
    });

    testWidgets('Voltar retorna ao passo 1', (tester) async {
      await pumpModal(tester);
      await goToStep2(tester);
      await tester.ensureVisible(find.text('Voltar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voltar'));
      await tester.pumpAndSettle();
      expect(find.text('Nova Empresa'), findsOneWidget);
    });

    testWidgets('salva na carteira, leva o responsável ao CRM e fecha com true',
        (tester) async {
      final results = await pumpModal(tester);
      await goToStep2(tester);
      await tester.enterText(
          campo('Nome completo do responsável'), ' João da Silva ');
      await tapSalvar(tester);

      verify(() => service.saveCompany('g1', any(), -26.48, -49.07, 'ROOFTOP'))
          .called(1);
      verify(() => crm.addContactToCompany(
            cnpj: '12345678000199',
            nome: 'João da Silva',
            telefone: '47999999999',
            email: 'a@b.com',
          )).called(1);
      expect(results, [true]);
    });

    testWidgets('CRM fora do ar: avisa, não fecha e reenviar funciona',
        (tester) async {
      var falhar = true;
      when(() => crm.addContactToCompany(
            cnpj: any(named: 'cnpj'),
            nome: any(named: 'nome'),
            telefone: any(named: 'telefone'),
            email: any(named: 'email'),
          )).thenAnswer((_) async {
        if (falhar) throw 'CRM indisponível';
      });
      final results = await pumpModal(tester);
      await goToStep2(tester);
      await tapSalvar(tester);

      expect(find.textContaining('salva na carteira, mas não chegou ao CRM'),
          findsOneWidget);
      expect(results, isEmpty, reason: 'o modal continua aberto');

      falhar = false;
      await tapSalvar(tester);
      verify(() => service.saveCompany(any(), any(), any(), any(), any()))
          .called(2);
      expect(results, [true]);
    });

    testWidgets('sem organização ativa não valida nem consulta nada',
        (tester) async {
      await pumpModal(tester, withGroup: false);
      await goToStep2(tester);

      expect(find.text('Entre em uma organização para cadastrar empresas.'),
          findsOneWidget);
      verifyNever(() => service.cnpjInPortfolio(any(), any()));
      verifyNever(() => service.fetchCompanyData(any()));
    });

    testWidgets('mostra o erro quando salvar falha', (tester) async {
      when(() => service.saveCompany(any(), any(), any(), any(), any()))
          .thenThrow('Falha ao salvar');
      await pumpModal(tester);
      await goToStep2(tester);
      await tapSalvar(tester);
      expect(find.text('Falha ao salvar'), findsOneWidget);
    });
  });
}
