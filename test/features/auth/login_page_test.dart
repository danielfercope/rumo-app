import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/auth/login_page.dart';
import 'package:rumo_app/features/auth/privacy_policy_page.dart';
import 'package:rumo_app/features/auth/register_page.dart';

void main() {
  Future<void> pumpLoginPage(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CupertinoApp(home: LoginPage()),
      ),
    );
  }

  testWidgets('mostra erro ao tentar entrar com e-mail e senha vazios',
      (tester) async {
    await pumpLoginPage(tester);

    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Preencha e-mail e senha.'), findsOneWidget);
  });

  testWidgets('mostra erro ao tentar entrar só com e-mail preenchido',
      (tester) async {
    await pumpLoginPage(tester);

    await tester.enterText(
        find.byType(CupertinoTextField).first, 'teste@rumo.com');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Preencha e-mail e senha.'), findsOneWidget);
  });

  testWidgets('navega para a tela de cadastro ao tocar em "Criar conta"',
      (tester) async {
    await pumpLoginPage(tester);

    final criarConta = find.text('Criar conta');
    await tester.ensureVisible(criarConta);
    await tester.pumpAndSettle();
    await tester.tap(criarConta);
    await tester.pumpAndSettle();

    expect(find.byType(RegisterPage), findsOneWidget);
  });

  testWidgets('navega para a política de privacidade', (tester) async {
    await pumpLoginPage(tester);

    final politicaPrivacidade = find.text('Política de Privacidade');
    await tester.ensureVisible(politicaPrivacidade);
    await tester.pumpAndSettle();
    await tester.tap(politicaPrivacidade);
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPolicyPage), findsOneWidget);
  });
}
