import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/presentation/group_management_view.dart';
import 'package:rumo_app/features/groups/presentation/group_onboarding_view.dart';
import 'package:rumo_app/features/groups/presentation/groups_home_page.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';

void main() {
  var fetches = 0;

  Future<void> pump(
    WidgetTester tester,
    Future<List<MyGroup>> Function() groups,
  ) async {
    fetches = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myGroupsProvider.overrideWith((ref) {
          fetches++;
          return groups();
        }),
        groupMembersProvider('g1').overrideWith((ref) async => []),
      ],
      child: const CupertinoApp(home: GroupsHomePage()),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('sem grupos mostra o onboarding', (tester) async {
    await pump(tester, () async => []);

    expect(find.text('Organização'), findsOneWidget);
    expect(find.byType(GroupOnboardingView), findsOneWidget);
  });

  testWidgets('com grupo mostra a gestão', (tester) async {
    await pump(
        tester,
        () async => [
              MyGroup(
                group: Group(
                  id: 'g1',
                  name: 'Agro Sul',
                  trackingEnabled: false,
                  createdBy: 'u1',
                  createdAt: DateTime(2026, 1, 1),
                ),
                role: 'member',
                joinedAt: DateTime(2026, 1, 1),
              ),
            ]);

    expect(find.byType(GroupManagementView), findsOneWidget);
    expect(find.text('Agro Sul'), findsOneWidget);
  });

  testWidgets('enquanto carrega mostra o indicador', (tester) async {
    await pump(tester, () => Completer<List<MyGroup>>().future);

    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });

  testWidgets('erro mostra a mensagem e Tentar novamente busca de novo',
      (tester) async {
    await pump(tester, () async => throw Exception('sem rede'));
    expect(
        find.text('Não foi possível carregar sua organização'), findsOneWidget);
    expect(find.textContaining('sem rede'), findsOneWidget);
    final before = fetches;

    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();
    await tester.pump();

    expect(fetches, greaterThan(before));
  });
}
