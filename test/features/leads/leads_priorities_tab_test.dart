import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/carteira/models/crm_models.dart';
import 'package:rumo_app/features/carteira/models/priority_models.dart';
import 'package:rumo_app/features/carteira/providers/carteira_provider.dart';
import 'package:rumo_app/features/carteira/services/carteira_service.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';
import 'package:rumo_app/features/leads/leads_page.dart';
import 'package:rumo_app/features/map/providers/company_provider.dart';

import '../../helpers/fakes.dart';

class MockCarteiraService extends Mock implements CarteiraService {}

void main() {
  late MockCarteiraService service;
  late ProviderContainer container;

  final group = MyGroup(
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

  setUp(() {
    service = MockCarteiraService();
    when(() => service.buscarConexao('g1')).thenAnswer((_) async =>
        const CrmConnection(id: 'c1', provedor: 'hubspot', situacao: 'ativa'));
    when(() => service.prioridade('g1'))
        .thenAnswer((_) async => const PriorityResult(
              estrategia: PriorityStrategy.interacao,
              nClientes: 3,
              nLeads: 1,
              minimoClientesPerfil: 10,
              itens: [
                PriorityItem(
                  posicao: 1,
                  companyId: 'c1',
                  nome: 'Farmácia Alfa',
                  motivos: ['5 interações · no CRM há 152 dias'],
                ),
              ],
            ));
  });

  Future<void> pump(WidgetTester tester) async {
    container = ProviderContainer(overrides: [
      companyRepositoryProvider
          .overrideWithValue(FakeCompanyRepository(companies: [])),
      activeGroupProvider.overrideWithValue(group),
      carteiraServiceProvider.overrideWithValue(service),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: LeadsPage()),
    ));
    await tester.pump();
  }

  Future<void> tapMode(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('abre em Buscar: campo de busca visível, sem prioridades',
      (tester) async {
    await pump(tester);

    expect(find.byType(CupertinoSearchTextField), findsOneWidget);
    expect(find.text('Prioridades'), findsOneWidget); // o segmento
    expect(find.text('Farmácia Alfa'), findsNothing);
    verifyNever(() => service.prioridade(any(), limit: any(named: 'limit')));
  });

  testWidgets('trocar pra Prioridades troca a busca pela lista, e volta',
      (tester) async {
    await pump(tester);

    await tapMode(tester, 'Prioridades');

    expect(find.byType(CupertinoSearchTextField), findsNothing);
    expect(find.text('Farmácia Alfa'), findsOneWidget);
    expect(find.text('5 interações · no CRM há 152 dias'), findsOneWidget);

    await tapMode(tester, 'Buscar');

    expect(find.byType(CupertinoSearchTextField), findsOneWidget);
    expect(find.text('Farmácia Alfa'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('puxar pra atualizar reconsulta as prioridades', (tester) async {
    await pump(tester);
    await tapMode(tester, 'Prioridades');
    clearInteractions(service);

    await tester.fling(find.text('Farmácia Alfa'), const Offset(0, 400), 1000);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    verify(() => service.prioridade('g1')).called(1); // só a do refresh

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
