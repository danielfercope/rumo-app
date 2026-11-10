import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/auth/privacy_policy_page.dart';
import 'package:rumo_app/features/auth/profile_page.dart';
import 'package:rumo_app/features/auth/providers/auth_provider.dart';
import 'package:rumo_app/features/auth/providers/profile_provider.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';

class MockAuthController extends Mock implements AuthController {}

void main() {
  late MockAuthController auth;

  UserProfile profile({
    String nome = 'Daniel Cope',
    String email = 'daniel@x.com',
    String departamento = 'Pré-vendas',
    String nivel = 'user',
  }) =>
      UserProfile(
        id: 'u1',
        email: email,
        nome: nome,
        departamento: departamento,
        nivelAcesso: nivel,
      );

  MyGroup mine(String name, String role) => MyGroup(
        group: Group(
          id: name,
          name: name,
          trackingEnabled: false,
          createdBy: 'u1',
          createdAt: DateTime(2026, 1, 1),
        ),
        role: role,
        joinedAt: DateTime(2026, 1, 1),
      );

  setUp(() {
    auth = MockAuthController();
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    Future<UserProfile?> Function()? profileFuture,
    Future<List<MyGroup>> Function()? groups,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWithValue(auth),
        userPhotoProvider.overrideWith((ref) async => null),
        profileProvider.overrideWith((ref) =>
            profileFuture != null ? profileFuture() : Future.value(profile())),
        myGroupsProvider.overrideWith((ref) => groups != null
            ? groups()
            : Future.value([mine('Agro Sul', 'admin')])),
      ],
      child: const CupertinoApp(home: ProfilePage()),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('mostra identidade, permissões e grupos do usuário',
      (tester) async {
    await pump(tester);

    expect(find.text('Daniel Cope'), findsOneWidget);
    expect(find.text('daniel@x.com'), findsWidgets);
    expect(find.text('Pré-vendas'), findsOneWidget);
    expect(find.text('Usuário'), findsOneWidget);
    expect(find.text('Permitido'), findsOneWidget); // Pré-vendas pode cadastrar
    expect(find.text('Agro Sul'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('DC'), findsOneWidget); // avatar com iniciais
  });

  testWidgets('administrador: rótulo próprio e departamento vazio vira traço',
      (tester) async {
    await pump(tester,
        profileFuture: () async => profile(nivel: 'admin', departamento: ''));

    expect(find.text('Administrador'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(
        find.text('Permitido'), findsOneWidget); // admin sempre pode cadastrar
  });

  testWidgets('convidado sem nome nem e-mail: rótulos de fallback',
      (tester) async {
    await pump(tester,
        profileFuture: () async => profile(
            nivel: 'guest', departamento: 'Vendas', nome: '', email: ''));

    expect(find.text('Convidado'), findsOneWidget);
    expect(find.text('Sem permissão'), findsOneWidget);
    expect(find.text('Sem nome'), findsOneWidget);
  });

  testWidgets('membro (não admin) aparece como Membro', (tester) async {
    await pump(tester, groups: () async => [mine('Agro Sul', 'member')]);
    expect(find.text('Membro'), findsOneWidget);
  });

  testWidgets('sem grupos mostra a mensagem', (tester) async {
    await pump(tester, groups: () async => []);
    expect(find.text('Você não participa de nenhum grupo'), findsOneWidget);
  });

  testWidgets('falha ao carregar os grupos não derruba a tela', (tester) async {
    await pump(tester, groups: () async => throw Exception('rede'));
    expect(find.text('Não foi possível carregar os grupos'), findsOneWidget);
    expect(find.text('Daniel Cope'), findsOneWidget);
  });

  testWidgets('enquanto carrega mostra o indicador', (tester) async {
    await pump(tester,
        profileFuture: () => Completer<UserProfile?>().future,
        groups: () => Completer<List<MyGroup>>().future);
    expect(find.byType(CupertinoActivityIndicator), findsWidgets);
  });

  testWidgets('erro no perfil mostra a mensagem', (tester) async {
    await pump(tester, profileFuture: () async => throw Exception('falhou'));
    expect(find.textContaining('Erro ao carregar o perfil'), findsOneWidget);
  });

  testWidgets('perfil nulo ainda mostra grupos e ações', (tester) async {
    await pump(tester, profileFuture: () async => null);
    expect(find.text('Conta'), findsNothing);
    expect(find.text('Sair da conta'), findsOneWidget);
  });

  testWidgets('abre a política de privacidade', (tester) async {
    await pump(tester);
    await tester.ensureVisible(find.text('Política de Privacidade'));
    await tester.tap(find.text('Política de Privacidade'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyPage), findsOneWidget);
  });

  group('sair da conta', () {
    Future<void> openDialog(WidgetTester tester) async {
      await pump(tester);
      await tester
          .ensureVisible(find.widgetWithText(CupertinoButton, 'Sair da conta'));
      await tester.tap(find.widgetWithText(CupertinoButton, 'Sair da conta'));
      await tester.pumpAndSettle();
    }

    testWidgets('confirmar chama signOut', (tester) async {
      await openDialog(tester);
      expect(find.textContaining('Você precisará entrar novamente'),
          findsOneWidget);

      await tester.tap(find.text('Sair'));
      await tester.pumpAndSettle();

      verify(() => auth.signOut()).called(1);
    });

    testWidgets('cancelar não sai da conta', (tester) async {
      await openDialog(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => auth.signOut());
    });
  });
}
