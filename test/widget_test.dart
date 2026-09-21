import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:rumo_app/main.dart';
import 'package:rumo_app/features/auth/providers/auth_provider.dart';
import 'package:rumo_app/features/auth/login_page.dart';

void main() {
  testWidgets('Sem sessão ativa, RumoApp renderiza a LoginPage',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) =>
                Stream.value(const AuthState(AuthChangeEvent.signedOut, null)),
          ),
        ],
        child: const RumoApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(LoginPage), findsOneWidget);
  });
}
