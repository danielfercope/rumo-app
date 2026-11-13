import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/carteira/models/crm_models.dart';
import 'package:rumo_app/features/carteira/presentation/crm_connection_wizard.dart';
import 'package:rumo_app/features/carteira/providers/carteira_provider.dart';
import 'package:rumo_app/features/carteira/services/carteira_service.dart';

class MockCarteiraService extends Mock implements CarteiraService {}

const _cnpjProp = CrmProperty(name: 'cnpj', label: 'CNPJ', type: 'string');
const _nameProp = CrmProperty(name: 'name', label: 'Nome', type: 'string');
const _stageProp = CrmProperty(
  name: 'lifecyclestage',
  label: 'Estágio',
  type: 'enumeration',
  options: [
    CrmOption(value: 'lead', label: 'Lead'),
    CrmOption(value: 'customer', label: 'Cliente'),
    CrmOption(value: 'other', label: 'Outro'),
  ],
);

const _preview = CrmPreview(
  totalComCnpj: 10,
  validos: 8,
  cnpjInvalido: 2,
  clientes: 3,
  leads: 4,
  perdidos: 1,
  truncado: false,
);

void main() {
  late MockCarteiraService service;
  bool? result;

  setUpAll(() {
    registerFallbackValue(const CrmMapping(campoCnpj: 'a', campoStatus: 'b'));
  });

  setUp(() {
    service = MockCarteiraService();
    result = null;
  });

  Future<void> pump(WidgetTester tester) async {
    // o assistente é mais alto que o viewport padrão do teste (800x600)
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [carteiraServiceProvider.overrideWithValue(service)],
      child: CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                child: const Text('abrir'),
                onPressed: () async {
                  result = await Navigator.push<bool>(
                    context,
                    CupertinoPageRoute(
                        builder: (_) =>
                            const CrmConnectionWizard(groupId: 'g1')),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> enterTokenAndValidate(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const ValueKey('token-field')), 'pat-123');
    await tester.pump();
    await tester.tap(find.text('Validar token'));
    await tester.pumpAndSettle();
  }

  void stubValidate(List<CrmProperty> props) =>
      when(() => service.validar('g1', 'pat-123'))
          .thenAnswer((_) async => props);

  testWidgets('o campo do token é ofuscado e o botão só habilita com texto',
      (tester) async {
    await pump(tester);

    final field = tester
        .widget<CupertinoTextField>(find.byKey(const ValueKey('token-field')));
    expect(field.obscureText, isTrue);
    expect(field.autocorrect, isFalse);

    await tester.tap(find.text('Validar token')); // vazio: não faz nada
    await tester.pump();
    verifyNever(() => service.validar(any(), any()));
  });

  testWidgets('fluxo completo: token, campos, prévia e conectar',
      (tester) async {
    stubValidate([_cnpjProp, _nameProp, _stageProp]);
    when(() => service.previa(any(), any(), any()))
        .thenAnswer((_) async => _preview);
    when(() => service.conectar(any(), any(), any())).thenAnswer((_) async {});

    await pump(tester);
    await enterTokenAndValidate(tester);

    // Passo 2: campos pré-selecionados e "customer" já como Cliente.
    expect(find.text('Passo 2 de 3'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('pick-cnpj')),
            matching: find.text('CNPJ')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('pick-status')),
            matching: find.text('Estágio')),
        findsOneWidget);
    await tester.tap(find.text('Ver prévia'));
    await tester.pumpAndSettle();

    final mapping = verify(() => service.previa('g1', 'pat-123', captureAny()))
        .captured
        .single as CrmMapping;
    expect(mapping.campoCnpj, 'cnpj');
    expect(mapping.campoStatus, 'lifecyclestage');
    expect(mapping.valoresCliente, ['customer']);
    expect(mapping.valoresPerdido, isEmpty);

    // Passo 3.
    expect(find.text('Passo 3 de 3'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('empresas com CNPJ válido'), findsOneWidget);
    for (final (key, n) in [
      ('clientes', '3'),
      ('leads', '4'),
      ('perdidas', '1')
    ]) {
      expect(
          find.descendant(
              of: find.byKey(ValueKey('stat-$key')), matching: find.text(n)),
          findsOneWidget);
    }
    expect(find.textContaining('2 empresas serão ignoradas'), findsOneWidget);

    await tester.tap(find.text('Conectar e importar'));
    await tester.pumpAndSettle();

    verify(() => service.conectar('g1', 'pat-123', any())).called(1);
    expect(result, isTrue);
    expect(find.text('abrir'), findsOneWidget); // assistente fechou
  });

  testWidgets('token recusado mostra o motivo e continua no passo 1',
      (tester) async {
    when(() => service.validar(any(), any())).thenThrow(ApiException(
        'O CRM recusou o token (inválido, revogado ou sem '
        'permissão).',
        statusCode: 400));

    await pump(tester);
    await enterTokenAndValidate(tester);

    expect(find.textContaining('O CRM recusou o token'), findsOneWidget);
    expect(find.text('Passo 1 de 3'), findsOneWidget);
    verifyNever(() => service.conectar(any(), any(), any()));
  });

  testWidgets('o usuário reclassifica um estágio como Perdido', (tester) async {
    stubValidate([_cnpjProp, _stageProp]);
    when(() => service.previa(any(), any(), any()))
        .thenAnswer((_) async => _preview);

    await pump(tester);
    await enterTokenAndValidate(tester);
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('classe-other')),
        matching: find.text('Perdido')));
    await tester.pump();
    await tester.tap(find.text('Ver prévia'));
    await tester.pumpAndSettle();

    final mapping = verify(() => service.previa(any(), any(), captureAny()))
        .captured
        .single as CrmMapping;
    expect(mapping.valoresPerdido, ['other']);
    expect(mapping.valoresCliente, ['customer']);
  });

  testWidgets(
      'sem campo de lista, o estágio vira valores separados por vírgula',
      (tester) async {
    const situacao =
        CrmProperty(name: 'situacao', label: 'Situação', type: 'string');
    stubValidate([_cnpjProp, situacao]);
    when(() => service.previa(any(), any(), any()))
        .thenAnswer((_) async => _preview);

    await pump(tester);
    await enterTokenAndValidate(tester);

    // Nada pré-selecionado: não dá pra seguir sem escolher o campo do estágio.
    await tester.tap(find.text('Ver prévia'));
    await tester.pump();
    verifyNever(() => service.previa(any(), any(), any()));

    await tester.tap(find.byKey(const ValueKey('pick-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Situação (situacao)'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('valores-cliente')), 'ativo, vip ,');
    await tester.enterText(
        find.byKey(const ValueKey('valores-perdido')), 'churn');
    await tester.tap(find.text('Ver prévia'));
    await tester.pumpAndSettle();

    final mapping = verify(() => service.previa(any(), any(), captureAny()))
        .captured
        .single as CrmMapping;
    expect(mapping.campoStatus, 'situacao');
    expect(mapping.valoresCliente, ['ativo', 'vip']);
    expect(mapping.valoresPerdido, ['churn']);
  });

  testWidgets('prévia sem empresas válidas bloqueia a conexão', (tester) async {
    stubValidate([_cnpjProp, _stageProp]);
    when(() => service.previa(any(), any(), any())).thenAnswer((_) async =>
        const CrmPreview(
            totalComCnpj: 3,
            validos: 0,
            cnpjInvalido: 3,
            clientes: 0,
            leads: 0,
            perdidos: 0,
            truncado: false));

    await pump(tester);
    await enterTokenAndValidate(tester);
    await tester.tap(find.text('Ver prévia'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('previa-vazia')), findsOneWidget);
    await tester.tap(find.text('Conectar e importar'));
    await tester.pump();
    verifyNever(() => service.conectar(any(), any(), any()));
  });

  testWidgets('falha ao conectar mostra o erro e não fecha o assistente',
      (tester) async {
    stubValidate([_cnpjProp, _stageProp]);
    when(() => service.previa(any(), any(), any()))
        .thenAnswer((_) async => _preview);
    when(() => service.conectar(any(), any(), any())).thenThrow(ApiException(
        'Apenas administradores da organização podem gerenciar o CRM.',
        statusCode: 403));

    await pump(tester);
    await enterTokenAndValidate(tester);
    await tester.tap(find.text('Ver prévia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conectar e importar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Apenas administradores'), findsOneWidget);
    expect(find.text('Passo 3 de 3'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('Voltar retorna ao passo anterior; Cancelar fecha com false',
      (tester) async {
    stubValidate([_cnpjProp, _stageProp]);

    await pump(tester);
    await enterTokenAndValidate(tester);
    await tester.tap(find.text('Voltar'));
    await tester.pump();
    expect(find.text('Passo 1 de 3'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
