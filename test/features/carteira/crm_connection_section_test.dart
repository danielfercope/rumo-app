import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/carteira/models/crm_models.dart';
import 'package:rumo_app/features/carteira/presentation/crm_connection_section.dart';
import 'package:rumo_app/features/carteira/providers/carteira_provider.dart';
import 'package:rumo_app/features/carteira/services/carteira_service.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/providers/company_provider.dart';

class MockCarteiraService extends Mock implements CarteiraService {}

void main() {
  late MockCarteiraService service;

  CrmConnection conn(String situacao, {String? erro, DateTime? sync}) =>
      CrmConnection(
        id: 'c1',
        provedor: 'hubspot',
        situacao: situacao,
        ultimoErro: erro,
        ultimaSincronizacao: sync,
      );

  final log = SyncLog(
    tipo: 'carga_inicial',
    situacao: 'concluida',
    lidas: 312,
    novas: 87,
    atualizadas: 5,
    falhas: 2,
    iniciadaEm: DateTime(2026, 11, 8, 12),
  );

  setUp(() {
    service = MockCarteiraService();
    when(() => service.ultimaSincronizacao(any()))
        .thenAnswer((_) async => null);
  });

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      carteiraServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: SingleChildScrollView(
              child: CrmConnectionSection(groupId: 'g1'),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return container;
  }

  // Descarta a árvore: o provider autoDispose cancela o timer de polling.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('sem conexão: convida a conectar o HubSpot', (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer((_) async => null);

    await pump(tester);

    expect(find.text('Integração com CRM'), findsOneWidget);
    expect(find.textContaining('Nenhum CRM conectado'), findsOneWidget);
    expect(find.text('Conectar HubSpot'), findsOneWidget);
    expect(find.text('Desconectar'), findsNothing);
  });

  testWidgets('conectado: mostra a última sincronização e o resumo da carga',
      (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer(
        (_) async => conn('ativa', sync: DateTime(2026, 11, 8, 9, 5)));
    when(() => service.ultimaSincronizacao('g1')).thenAnswer((_) async => log);

    await pump(tester);

    expect(find.textContaining('HubSpot conectado'), findsOneWidget);
    expect(find.textContaining('08/11/2026 09:05'), findsOneWidget);
    expect(
        find.text(
            'Última carga: 312 lidas · 87 novas · 5 atualizadas · 2 com falha'),
        findsOneWidget);
    expect(find.text('Sincronizar agora'), findsOneWidget);
    expect(find.text('Reconectar'), findsOneWidget);
    expect(find.text('Desconectar'), findsOneWidget);
  });

  testWidgets('erro: mostra a mensagem do servidor', (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer(
        (_) async => conn('erro', erro: 'O CRM recusou o token (revogado)'));

    await pump(tester);

    expect(find.text('Problema na integração'), findsOneWidget);
    expect(find.textContaining('recusou o token'), findsOneWidget);
  });

  testWidgets(
      'importando: mostra o progresso, esconde "Sincronizar agora" e '
      'reconsulta até terminar', (tester) async {
    var calls = 0;
    when(() => service.buscarConexao('g1')).thenAnswer((_) async {
      calls++;
      return calls == 1 ? conn('pendente') : conn('ativa');
    });

    await pump(tester);
    expect(find.text('Importando sua carteira'), findsOneWidget);
    expect(find.text('Sincronizar agora'), findsNothing);

    await tester.pump(crmPollInterval);
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.textContaining('HubSpot conectado'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('importando: mostra quantas empresas já foram e a estimativa',
      (tester) async {
    when(() => service.buscarConexao('g1'))
        .thenAnswer((_) async => conn('pendente'));
    when(() => service.ultimaSincronizacao('g1')).thenAnswer(
      (_) async => SyncLog(
        tipo: 'carga_inicial',
        situacao: 'em_andamento',
        lidas: 300,
        novas: 228,
        atualizadas: 0,
        falhas: 0,
        iniciadaEm: DateTime.now().subtract(const Duration(minutes: 4)),
        processadas: 230,
        estimado: 502,
      ),
    );

    await pump(tester);

    expect(find.byKey(const ValueKey('import-percent')), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);
    expect(find.textContaining('230 de 502 empresas'), findsOneWidget);
    expect(find.textContaining('faltam'), findsOneWidget);
    // o resumo "Última carga" só aparece quando termina
    expect(find.textContaining('Última carga'), findsNothing);
    await unmount(tester);
    await tester.pump(crmPollInterval); // deixa o autoDispose cancelar o timer
    await tester.pump();
  });

  testWidgets(
      'falha transitória na carga inicial não fica "importando" '
      'para sempre', (tester) async {
    when(() => service.buscarConexao('g1'))
        .thenAnswer((_) async => conn('pendente', erro: 'CRM respondeu 429'));

    await pump(tester);

    expect(find.text('Problema na integração'), findsOneWidget);
    expect(find.text('Importando sua carteira'), findsNothing);
    expect(find.text('Sincronizar agora'), findsOneWidget); // dá pra retentar
  });

  testWidgets('ao terminar a carga inicial o mapa é recarregado',
      (tester) async {
    var calls = 0;
    when(() => service.buscarConexao('g1')).thenAnswer((_) async {
      calls++;
      return calls == 1 ? conn('pendente') : conn('ativa');
    });
    var companiesBuilds = 0;
    final container = ProviderContainer(overrides: [
      carteiraServiceProvider.overrideWithValue(service),
      companiesProvider.overrideWith((ref) async {
        companiesBuilds++;
        return <Company>[];
      }),
    ]);
    addTearDown(container.dispose);
    container.listen(companiesProvider, (_, __) {}); // mantém vivo
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: CrmConnectionSection(groupId: 'g1'),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(companiesBuilds, 1);

    await tester.pump(crmPollInterval);
    await tester.pump();
    await tester.pump();

    expect(companiesBuilds, 2);
    await unmount(tester);
  });

  testWidgets(
      'desconectar e apagar a carteira pede confirmação e chama o '
      'service', (tester) async {
    when(() => service.buscarConexao('g1'))
        .thenAnswer((_) async => conn('ativa'));
    when(() => service.desconectar(any(),
        apagarCarteira: any(named: 'apagarCarteira'))).thenAnswer((_) async {});

    await pump(tester);
    await tester.tap(find.text('Desconectar'));
    await tester.pumpAndSettle();
    expect(find.text('Desconectar e manter a carteira'), findsOneWidget);
    await tester.tap(find.text('Desconectar e apagar a carteira importada'));
    await tester.pumpAndSettle();

    verify(() => service.desconectar('g1', apagarCarteira: true)).called(1);
  });

  testWidgets('cancelar o menu de desconexão não faz nada', (tester) async {
    when(() => service.buscarConexao('g1'))
        .thenAnswer((_) async => conn('ativa'));

    await pump(tester);
    await tester.tap(find.text('Desconectar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    verifyNever(() => service.desconectar(any(),
        apagarCarteira: any(named: 'apagarCarteira')));
  });

  testWidgets('sincronizar agora dispara no servidor e recarrega o status',
      (tester) async {
    when(() => service.buscarConexao('g1'))
        .thenAnswer((_) async => conn('ativa'));
    when(() => service.sincronizarAgora(any())).thenAnswer((_) async {});

    await pump(tester);
    await tester.tap(find.text('Sincronizar agora'));
    await tester.pumpAndSettle();
    expect(find.text('Sincronização iniciada'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump();

    verify(() => service.sincronizarAgora('g1')).called(1);
    verify(() => service.buscarConexao('g1')).called(1);
    await tester.pump(const Duration(seconds: 5)); // espera o recarregamento
    await tester.pump();
    verify(() => service.buscarConexao('g1')).called(1);
  });

  testWidgets('erro do backend aparece num alerta com a mensagem',
      (tester) async {
    when(() => service.buscarConexao('g1'))
        .thenAnswer((_) async => conn('ativa'));
    when(() => service.sincronizarAgora(any())).thenThrow(
        ApiException('Já há uma sincronização em andamento.', statusCode: 409));

    await pump(tester);
    await tester.tap(find.text('Sincronizar agora'));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível concluir'), findsOneWidget);
    expect(find.text('Já há uma sincronização em andamento.'), findsOneWidget);
  });

  testWidgets('"Conectar HubSpot" abre o assistente', (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer((_) async => null);

    await pump(tester);
    await tester.tap(find.text('Conectar HubSpot'));
    await tester.pumpAndSettle();

    expect(find.text('Validar token'), findsOneWidget);
    expect(find.text('Passo 1 de 3'), findsOneWidget);
  });
}
