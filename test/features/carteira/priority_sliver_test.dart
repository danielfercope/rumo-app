import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/carteira/models/crm_models.dart';
import 'package:rumo_app/features/carteira/models/priority_models.dart';
import 'package:rumo_app/features/carteira/presentation/priority_sliver.dart';
import 'package:rumo_app/features/carteira/providers/carteira_provider.dart';
import 'package:rumo_app/features/carteira/services/carteira_service.dart';
import 'package:rumo_app/features/company/crm_service.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';
import 'package:rumo_app/features/map/presentation/company_details_modal.dart';

class MockCarteiraService extends Mock implements CarteiraService {}

final _group = MyGroup(
  group: Group(
    id: 'g1',
    name: 'Equipe',
    trackingEnabled: false,
    createdBy: 'u1',
    createdAt: DateTime(2026),
  ),
  role: 'member',
  joinedAt: DateTime(2026),
);

CrmConnection _conn({String situacao = 'ativa', String? erro}) => CrmConnection(
      id: 'c1',
      provedor: 'hubspot',
      situacao: situacao,
      ultimoErro: erro,
    );

PriorityResult _result({
  PriorityStrategy? estrategia = PriorityStrategy.interacao,
  int nClientes = 3,
  int nLeads = 2,
  List<PriorityItem>? itens,
}) =>
    PriorityResult(
      estrategia: estrategia,
      nClientes: nClientes,
      nLeads: nLeads,
      minimoClientesPerfil: 10,
      itens: itens ?? const [],
    );

void main() {
  late MockCarteiraService service;
  late ProviderContainer container;
  var disposed = false;

  setUp(() {
    service = MockCarteiraService();
  });

  Future<void> pump(WidgetTester tester, {MyGroup? group}) async {
    disposed = false;
    container = ProviderContainer(overrides: [
      carteiraServiceProvider.overrideWithValue(service),
      activeGroupProvider.overrideWithValue(group),
      crmNotesProvider.overrideWith((ref, cnpj) async => <CrmNote>[]),
      crmContactsProvider.overrideWith((ref, cnpj) async => <CrmContact>[]),
    ]);
    addTearDown(() {
      if (!disposed) container.dispose();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(
        home: CupertinoPageScaffold(
          child: CustomScrollView(slivers: [PrioritySliver()]),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  // Desmonta a tela e descarta o container na hora: no teste o autoDispose não
  // roda sozinho após o unmount, e o Timer de polling ficaria pendente.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    disposed = true;
  }

  testWidgets('sem organização ativa, pede pra entrar em uma', (tester) async {
    await pump(tester);

    expect(find.textContaining('Entre em uma organização'), findsOneWidget);
    verifyNever(() => service.buscarConexao(any()));
  });

  testWidgets('sem CRM conectado: orienta e não consulta prioridades',
      (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer((_) async => null);

    await pump(tester, group: _group);

    expect(find.textContaining('Conecte seu CRM'), findsOneWidget);
    verifyNever(() => service.prioridade(any(), limit: any(named: 'limit')));
  });

  testWidgets('conectado mas sem cálculo: mostra "calculando" e se reconsulta',
      (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer((_) async => _conn());
    when(() => service.prioridade('g1'))
        .thenAnswer((_) async => _result(estrategia: null, nLeads: 0));

    await pump(tester, group: _group);

    expect(find.textContaining('Calculando as prioridades'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    verify(() => service.prioridade('g1')).called(1);

    await tester.pump(crmPollInterval);
    await tester.pump();
    await tester.pump();
    verify(() => service.prioridade('g1')).called(1); // segunda consulta

    await unmount(tester);
  });

  testWidgets('conexão com erro e nunca calculou: avisa e não fica consultando',
      (tester) async {
    when(() => service.buscarConexao('g1'))
        .thenAnswer((_) async => _conn(situacao: 'erro', erro: 'token'));
    when(() => service.prioridade('g1'))
        .thenAnswer((_) async => _result(estrategia: null, nLeads: 0));

    await pump(tester, group: _group);
    expect(find.textContaining('com problema'), findsOneWidget);

    await tester.pump(crmPollInterval * 3);
    verify(() => service.prioridade('g1')).called(1);
    await unmount(tester);
  });

  testWidgets(
      'interação: mostra ordem e motivos sempre visíveis, sem nota nem barra',
      (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer((_) async => _conn());
    when(() => service.prioridade('g1')).thenAnswer(
      (_) async => _result(itens: const [
        PriorityItem(
          posicao: 1,
          companyId: 'c1',
          nome: 'Farmácia Alfa',
          municipio: 'Joinville',
          uf: 'SC',
          motivos: ['5 interações · no CRM há 152 dias'],
        ),
        PriorityItem(
          posicao: 2,
          companyId: 'c2',
          nome: 'Mercado Beta',
          motivos: ['1 interação'],
        ),
      ]),
    );

    await pump(tester, group: _group);

    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Farmácia Alfa'), findsOneWidget);
    expect(find.text('Joinville / SC'), findsOneWidget);
    expect(find.text('5 interações · no CRM há 152 dias'), findsOneWidget);
    expect(find.text('1 interação'), findsOneWidget);
    expect(find.byKey(const ValueKey('score-bar-fill')), findsNothing);
    // explica o método e quanto falta pra mudar
    expect(find.textContaining('Ordenado por interação'), findsOneWidget);
    expect(find.textContaining('com mais 7'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('perfil: mostra a nota com barra proporcional e os motivos',
      (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer((_) async => _conn());
    when(() => service.prioridade('g1')).thenAnswer(
      (_) async => _result(
        estrategia: PriorityStrategy.perfil,
        nClientes: 40,
        nLeads: 120,
        itens: const [
          PriorityItem(
            posicao: 1,
            companyId: 'c1',
            nome: 'Farmácia Alfa',
            nota: 80,
            motivos: ['Segmento: farmácia (90% dos seus clientes, 8% da base)'],
          ),
        ],
      ),
    );

    await pump(tester, group: _group);

    expect(find.text('80'), findsOneWidget);
    final fill = tester.widget<FractionallySizedBox>(find
        .ancestor(
            of: find.byKey(const ValueKey('score-bar-fill')),
            matching: find.byType(FractionallySizedBox))
        .first);
    expect(fill.widthFactor, 0.8);
    expect(find.textContaining('Segmento: farmácia'), findsOneWidget);
    expect(find.textContaining('semelhança com o perfil dos seus 40 clientes'),
        findsOneWidget);
    expect(find.textContaining('1 primeiros de 120'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('carteira sem leads mostra mensagem vazia', (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer((_) async => _conn());
    when(() => service.prioridade('g1'))
        .thenAnswer((_) async => _result(nLeads: 0));

    await pump(tester, group: _group);

    expect(find.textContaining('Nenhum lead na sua carteira'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('conexão com erro mas com resultado antigo: mostra e avisa',
      (tester) async {
    when(() => service.buscarConexao('g1'))
        .thenAnswer((_) async => _conn(situacao: 'erro', erro: 'x'));
    when(() => service.prioridade('g1')).thenAnswer(
      (_) async => _result(itens: const [
        PriorityItem(posicao: 1, companyId: 'c1', nome: 'Alfa'),
      ], nLeads: 1),
    );

    await pump(tester, group: _group);

    expect(find.text('Alfa'), findsOneWidget);
    expect(find.textContaining('desatualizados'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('falha ao carregar mostra mensagem', (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer((_) async => _conn());
    when(() => service.prioridade('g1')).thenThrow(Exception('boom'));

    await pump(tester, group: _group);

    expect(find.textContaining('Não foi possível carregar'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('tocar numa empresa abre o detalhe dela', (tester) async {
    when(() => service.buscarConexao('g1')).thenAnswer((_) async => _conn());
    when(() => service.prioridade('g1')).thenAnswer(
      (_) async => _result(nLeads: 1, itens: const [
        PriorityItem(
          posicao: 1,
          companyId: 'c1',
          cnpj: '19131243000197',
          nome: 'Farmácia Alfa',
        ),
      ]),
    );

    await pump(tester, group: _group);
    await tester.tap(find.text('Farmácia Alfa'));
    await tester.pump();
    await tester.pump();

    final modal =
        tester.widget<CompanyDetailsModal>(find.byType(CompanyDetailsModal));
    expect(modal.company.cnpj, '19131243000197');
    expect(modal.company.name, 'Farmácia Alfa');
    await unmount(tester);
  });
}
