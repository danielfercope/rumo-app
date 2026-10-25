import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/auth/providers/profile_provider.dart';
import 'package:rumo_app/features/company/add_company_modal.dart';
import 'package:rumo_app/features/company/constants.dart';
import 'package:rumo_app/features/company/registration_service.dart';
import 'package:rumo_app/features/map/providers/location_provider.dart';

class MockRegistrationService extends Mock implements RegistrationService {}

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

void main() {
  late MockRegistrationService service;

  setUp(() {
    service = MockRegistrationService();
    when(() => service.cnpjExists(any())).thenAnswer((_) async => false);
    when(() => service.fetchCompanyData(any()))
        .thenAnswer((_) async => Map<String, dynamic>.from(_dadosApi));
    when(() => service.geocodeAddress(any())).thenAnswer(
        (_) async => (lat: -26.48, lon: -49.07, precisao: 'ROOFTOP'));
    when(() => service.isWithinProximity(any(), any(), any(), any()))
        .thenReturn(true);
    when(() => service.saveCompany(any(), any(), any(), any()))
        .thenAnswer((_) async {});
    when(() => service.sendToWebhook(any(), any(), any(), any()))
        .thenAnswer((_) async => true);
  });

  /// Abre o modal dentro de uma rota, pra conseguir observar o `pop(true)`.
  Future<List<Object?>> pumpModal(WidgetTester tester,
      {bool withLocation = true}) async {
    tester.view.physicalSize = const Size(2400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final results = <Object?>[];

    final container = ProviderContainer(overrides: [
      registrationServiceProvider.overrideWithValue(service),
      locationProvider.overrideWith((ref) => withLocation
          ? Future.value(_pos())
          : Completer<Position>().future),
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

  Future<void> pickFromSheet(
      WidgetTester tester, String fieldLabel, String option) async {
    final field = find.descendant(
      of: find
          .ancestor(of: find.text(fieldLabel), matching: find.byType(Column))
          .first,
      matching: find.byType(GestureDetector),
    );
    await tester.ensureVisible(field.first);
    await tester.pumpAndSettle();
    await tester.tap(field.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillSelects(WidgetTester tester) async {
    await pickFromSheet(tester,
        'Para quem a procuração eletrônica está habilitada?', kProcuracoes.first);
    await pickFromSheet(tester, 'Possui débitos?', 'Sim');
    await pickFromSheet(tester, 'Valor da dívida', kValoresDivida.first);
    await pickFromSheet(tester, 'Regime tributário', kRegimesTributarios.first);
    await pickFromSheet(tester, 'Análises a serem feitas', kAnalises.first);
    // Data
    final dateField = find.descendant(
      of: find
          .ancestor(
              of: find.text('Data de validade e-CAC'),
              matching: find.byType(Column))
          .first,
      matching: find.byType(GestureDetector),
    );
    await tester.ensureVisible(dateField.first);
    await tester.pumpAndSettle();
    await tester.tap(dateField.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await pickFromSheet(tester, 'Setor da empresa', kSetores.values.first);
    await pickFromSheet(tester, 'Departamentos', kDepartamentos.first);
    await pickFromSheet(tester, 'Tipo de lead', 'Novo lead');
    await pickFromSheet(tester, 'Prioridade', kPrioridades.values.first);
  }

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
      final field = tester.widget<CupertinoTextField>(
          find.byType(CupertinoTextField));
      expect(field.controller!.text, '12345678000199');
    });

    testWidgets('avisa quando a localização não está disponível',
        (tester) async {
      await pumpModal(tester, withLocation: false);
      await goToStep2(tester);
      expect(find.textContaining('Localização não disponível'),
          findsOneWidget);
    });

    testWidgets('bloqueia CNPJ já cadastrado', (tester) async {
      when(() => service.cnpjExists(any())).thenAnswer((_) async => true);
      await pumpModal(tester);
      await goToStep2(tester);
      expect(find.text('Esta empresa já está cadastrada.'), findsOneWidget);
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
    testWidgets('preenche os campos a partir da consulta', (tester) async {
      await pumpModal(tester);
      await goToStep2(tester);

      expect(find.text('Dados Complementares'), findsOneWidget);
      expect(find.text('Teste'), findsOneWidget);
      expect(find.text('Maria'), findsOneWidget); // primeiro nome
      expect(find.text('Lima'), findsOneWidget); // sobrenome
      expect(find.text('a@b.com'), findsOneWidget);
      expect(find.text('47999999999'), findsOneWidget);
    });

    testWidgets('sem sócio nos dados deixa os nomes vazios', (tester) async {
      when(() => service.fetchCompanyData(any())).thenAnswer((_) async => {
            'razao': 'Só Razão LTDA',
            'cnpj': '12345678000199',
          });
      await pumpModal(tester);
      await goToStep2(tester);
      expect(find.text('Só Razão LTDA'), findsOneWidget);
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

    testWidgets('enviar com campos pendentes lista os que faltam',
        (tester) async {
      await pumpModal(tester);
      await goToStep2(tester);
      await tester.ensureVisible(find.text('Salvar e Enviar para CRM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar e Enviar para CRM'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Preencha:'), findsOneWidget);
      expect(find.textContaining('Procuração'), findsOneWidget);
      verifyNever(() => service.saveCompany(any(), any(), any(), any()));
    });

    testWidgets('preenchimento completo salva, envia ao CRM e fecha com true',
        (tester) async {
      final results = await pumpModal(tester);
      await goToStep2(tester);
      await fillSelects(tester);

      await tester.ensureVisible(find.text('Salvar e Enviar para CRM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar e Enviar para CRM'));
      await tester.pumpAndSettle();

      verify(() => service.saveCompany(any(), -26.48, -49.07, 'ROOFTOP'))
          .called(1);
      final form = verify(() => service.sendToWebhook(
              any(), captureAny(), 'u@x.com', 'Usuária'))
          .captured
          .single as Map<String, dynamic>;
      expect(form['primeiro_nome'], 'Maria');
      expect(form['possui_debitos'], 'Sim');
      expect(form['tipo_lead'], 'Novo lead');
      expect(form['prioridade'], kPrioridades.keys.first);
      expect(form['setor_empresa'], kSetores.keys.first);
      expect(results, [true]);
    });

    testWidgets('mostra o erro quando salvar falha', (tester) async {
      when(() => service.saveCompany(any(), any(), any(), any()))
          .thenThrow('Falha ao salvar');
      await pumpModal(tester);
      await goToStep2(tester);
      await fillSelects(tester);
      await tester.ensureVisible(find.text('Salvar e Enviar para CRM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar e Enviar para CRM'));
      await tester.pumpAndSettle();
      expect(find.text('Falha ao salvar'), findsOneWidget);
    });

    testWidgets('cancelar o seletor de data e de ação não altera o valor',
        (tester) async {
      await pumpModal(tester);
      await goToStep2(tester);

      final debitos = find.descendant(
        of: find
            .ancestor(of: find.text('Possui débitos?'), matching: find.byType(Column))
            .first,
        matching: find.byType(GestureDetector),
      );
      await tester.ensureVisible(debitos.first);
      await tester.pumpAndSettle();
      await tester.tap(debitos.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      final data = find.descendant(
        of: find
            .ancestor(
                of: find.text('Data de validade e-CAC'),
                matching: find.byType(Column))
            .first,
        matching: find.byType(GestureDetector),
      );
      await tester.ensureVisible(data.first);
      await tester.pumpAndSettle();
      await tester.tap(data.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Sim'), findsNothing);
      expect(find.text('Selecione a data'), findsOneWidget);
    });

    testWidgets('a busca filtra opções e "Fechar" dispensa a folha',
        (tester) async {
      await pumpModal(tester);
      await goToStep2(tester);

      final regime = find.descendant(
        of: find
            .ancestor(of: find.text('Regime tributário'), matching: find.byType(Column))
            .first,
        matching: find.byType(GestureDetector),
      );
      await tester.ensureVisible(regime.first);
      await tester.pumpAndSettle();
      await tester.tap(regime.first);
      await tester.pumpAndSettle();

      final first = kRegimesTributarios.first;
      await tester.enterText(find.byType(CupertinoSearchTextField), 'zzzzzz');
      await tester.pump();
      expect(find.text(first), findsNothing);

      await tester.enterText(find.byType(CupertinoSearchTextField), '');
      await tester.pump();
      expect(find.text(first), findsOneWidget);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Fechar'), findsNothing);
    });
  });
}
