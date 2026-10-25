import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rumo_app/features/company/crm_service.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/presentation/company_details_modal.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../helpers/fakes.dart';

class MockCrmService extends Mock implements CrmService {}

class _FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  @override
  LinkDelegate? get linkDelegate => null;

  final launched = <String>[];
  bool canLaunchGoogle = false;
  bool canLaunchApple = false;

  @override
  Future<bool> canLaunch(String url) async {
    if (url.startsWith('comgooglemaps')) return canLaunchGoogle;
    if (url.startsWith('maps://')) return canLaunchApple;
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  late MockCrmService crm;
  late _FakeLauncher launcher;

  setUp(() {
    crm = MockCrmService();
    launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    when(() => crm.getNotesWithOwners(any())).thenAnswer((_) async => [
          CrmNote(
            id: 'n1',
            body: 'Ligou para o cliente',
            timestamp: DateTime(2026, 3, 5, 9, 7),
            ownerName: 'Ana',
          ),
          CrmNote(id: 'n2', body: 'Sem dono', timestamp: DateTime(2026, 3, 6)),
        ]);
    when(() => crm.getContacts(any())).thenAnswer((_) async => [
          const CrmContact(
              id: 'c1', nome: 'Carlos', telefone: '4799', email: 'c@x.com'),
          const CrmContact(id: 'c2', nome: 'Dora'),
        ]);
  });

  Future<void> pumpModal(WidgetTester tester, Company company) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [crmServiceProvider.overrideWithValue(crm)],
      child: CupertinoApp(
        home: CupertinoPageScaffold(child: CompanyDetailsModal(company: company)),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('mostra dados da empresa, notas e contatos do CRM',
      (tester) async {
    await pumpModal(tester, buildCompany());

    expect(find.text('Teste'), findsOneWidget);
    expect(find.text('Empresa Teste LTDA'), findsOneWidget);
    expect(find.text('12.345.678/0001-99'), findsOneWidget);
    expect(find.text('1.50 km de você'), findsOneWidget);
    expect(find.text('1.234.567,89'), findsOneWidget);
    expect(find.text('Dados de Crédito e Dívida'), findsOneWidget);
    expect(find.text('Carlos'), findsOneWidget);
    expect(find.text('c@x.com'), findsOneWidget);
    expect(find.text('Dora'), findsOneWidget);
    expect(find.text('Ligou para o cliente'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('05/03/2026 09:07'), findsOneWidget);
    expect(find.text('Usuário desconhecido'), findsOneWidget);
  });

  testWidgets('cliente não exibe a seção de crédito', (tester) async {
    await pumpModal(tester, buildCompany(isClient: true));
    expect(find.text('Dados de Crédito e Dívida'), findsNothing);
  });

  testWidgets('listas vazias do CRM mostram mensagens', (tester) async {
    when(() => crm.getNotesWithOwners(any())).thenAnswer((_) async => []);
    when(() => crm.getContacts(any())).thenAnswer((_) async => []);
    await pumpModal(tester, buildCompany());

    expect(find.text('Nenhum contato registrado no CRM.'), findsOneWidget);
    expect(find.textContaining('Nenhuma atividade registrada'), findsOneWidget);
  });

  testWidgets('falha no CRM mostra mensagens de erro', (tester) async {
    when(() => crm.getNotesWithOwners(any())).thenThrow(Exception('x'));
    when(() => crm.getContacts(any())).thenThrow(Exception('x'));
    await pumpModal(tester, buildCompany());

    expect(find.text('Não foi possível carregar os contatos do CRM.'),
        findsOneWidget);
    expect(find.text('Não foi possível carregar o histórico do CRM.'),
        findsOneWidget);
  });

  testWidgets('enquanto carrega mostra indicadores', (tester) async {
    final completer = Completer<List<CrmNote>>();
    when(() => crm.getNotesWithOwners(any()))
        .thenAnswer((_) => completer.future);
    when(() => crm.getContacts(any()))
        .thenAnswer((_) => Completer<List<CrmContact>>().future);
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [crmServiceProvider.overrideWithValue(crm)],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
            child: CompanyDetailsModal(company: buildCompany())),
      ),
    ));
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsNWidgets(2));
    completer.complete([]);
  });

  testWidgets('empresa sem CNPJ não consulta o CRM e avisa', (tester) async {
    await pumpModal(tester, buildCompany(cnpj: null));
    expect(find.text('CNPJ não disponível para busca no CRM.'),
        findsOneWidget);
    verifyNever(() => crm.getNotesWithOwners(any()));
  });

  testWidgets('sem nome fantasia usa a razão social e sem coordenadas esconde rota',
      (tester) async {
    await pumpModal(
        tester,
        buildCompany(
            fantasyName: null, latitude: null, longitude: null, cnpj: ''));
    expect(find.text('Empresa Teste LTDA'), findsOneWidget);
    expect(find.text('Traçar Rota'), findsNothing);
  });

  testWidgets('sem nome algum mostra "Empresa"', (tester) async {
    await pumpModal(tester, buildCompany(fantasyName: null, name: null));
    expect(find.text('Empresa'), findsOneWidget);
  });

  testWidgets('tocar no título copia e fecha o diálogo sozinho',
      (tester) async {
    await pumpModal(tester, buildCompany());
    await tester.tap(find.text('Teste'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Copiado'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Copiado'), findsNothing);
  });

  testWidgets('tocar em um campo copia o valor e o diálogo pode ser fechado',
      (tester) async {
    await pumpModal(tester, buildCompany());
    await tester.tap(find.text('47999999999'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Copiado'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Copiado'), findsNothing);
  });

  group('Traçar Rota', () {
    testWidgets('usa o Google Maps quando disponível', (tester) async {
      launcher.canLaunchGoogle = true;
      await pumpModal(tester, buildCompany());
      await tester.tap(find.text('Traçar Rota'));
      await tester.pumpAndSettle();
      expect(launcher.launched.single, startsWith('comgooglemaps://'));
    });

    testWidgets('cai para o Apple Maps', (tester) async {
      launcher.canLaunchApple = true;
      await pumpModal(tester, buildCompany());
      await tester.tap(find.text('Traçar Rota'));
      await tester.pumpAndSettle();
      expect(launcher.launched.single, startsWith('maps://'));
    });

    testWidgets('cai para o link web', (tester) async {
      await pumpModal(tester, buildCompany());
      await tester.tap(find.text('Traçar Rota'));
      await tester.pumpAndSettle();
      expect(launcher.launched.single, startsWith('https://www.google.com'));
    });
  });

  group('Nova Nota', () {
    setUp(() {
      when(() => crm.addNoteToCompany(
              cnpj: any(named: 'cnpj'), noteText: any(named: 'noteText')))
          .thenAnswer((_) async {});
    });

    testWidgets('não salva nota vazia', (tester) async {
      await pumpModal(tester, buildCompany());
      await tester.tap(find.text('Nova Nota'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      verifyNever(() => crm.addNoteToCompany(
          cnpj: any(named: 'cnpj'), noteText: any(named: 'noteText')));
    });

    testWidgets('salva, mostra sucesso e fecha a folha', (tester) async {
      await pumpModal(tester, buildCompany());
      await tester.tap(find.text('Nova Nota'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '  Retornar  ');
      await tester.tap(find.text('Salvar'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Nota salva com sucesso!'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
      expect(find.text('Nova Nota'), findsOneWidget); // só o botão
      expect(find.text('Nota salva com sucesso!'), findsNothing);
      verify(() => crm.addNoteToCompany(
          cnpj: '12345678000199', noteText: 'Retornar')).called(1);
    });

    testWidgets('mostra o erro quando o CRM falha', (tester) async {
      when(() => crm.addNoteToCompany(
              cnpj: any(named: 'cnpj'), noteText: any(named: 'noteText')))
          .thenThrow(Exception('CRM fora do ar'));
      await pumpModal(tester, buildCompany());
      await tester.tap(find.text('Nova Nota'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), 'abc');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('CRM fora do ar'), findsOneWidget);
    });

    testWidgets('Cancelar fecha a folha', (tester) async {
      await pumpModal(tester, buildCompany());
      await tester.tap(find.text('Nova Nota'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelar'), findsNothing);
    });
  });

  group('Novo Contato', () {
    setUp(() {
      when(() => crm.addContactToCompany(
            cnpj: any(named: 'cnpj'),
            nome: any(named: 'nome'),
            telefone: any(named: 'telefone'),
            email: any(named: 'email'),
          )).thenAnswer((_) async {});
    });

    Future<void> open(WidgetTester tester) async {
      await pumpModal(tester, buildCompany());
      await tester.tap(find.text('Novo Contato'));
      await tester.pumpAndSettle();
    }

    testWidgets('exige nome e telefone', (tester) async {
      await open(tester);
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Nome e telefone são obrigatórios.'), findsOneWidget);
    });

    testWidgets('salva sem e-mail enviando null', (tester) async {
      await open(tester);
      final fields = find.byType(CupertinoTextField);
      await tester.enterText(fields.at(0), 'Maria');
      await tester.enterText(fields.at(1), '47988');
      await tester.tap(find.text('Salvar'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Contato salvo com sucesso!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();

      verify(() => crm.addContactToCompany(
          cnpj: '12345678000199',
          nome: 'Maria',
          telefone: '47988',
          email: null)).called(1);
    });

    testWidgets('salva com e-mail e mostra erro se falhar', (tester) async {
      when(() => crm.addContactToCompany(
            cnpj: any(named: 'cnpj'),
            nome: any(named: 'nome'),
            telefone: any(named: 'telefone'),
            email: any(named: 'email'),
          )).thenThrow(Exception('Falhou'));
      await open(tester);
      final fields = find.byType(CupertinoTextField);
      await tester.enterText(fields.at(0), 'Maria');
      await tester.enterText(fields.at(1), '47988');
      await tester.enterText(fields.at(2), 'm@x.com');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('Falhou'), findsOneWidget);
    });

    testWidgets('Cancelar fecha a folha', (tester) async {
      await open(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelar'), findsNothing);
    });
  });
}
