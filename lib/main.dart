import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/login_page.dart';
import 'features/map/providers/auth_provider.dart';
import 'features/map/radar_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const ProviderScope(child: RumoApp()));
}
class RumoApp extends ConsumerWidget {
  const RumoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return CupertinoApp(
      title: 'RUMO',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.dark,
        primaryColor: CupertinoColors.systemYellow,
      ),
      home: authState.when(
        data: (state) {
          if (state.session != null) {
            return const MainNavigation();
          }
          return const LoginPage();
        },
        loading: () => const CupertinoPageScaffold(
          child: Center(child: CupertinoActivityIndicator()),
        ),
        error: (_, __) => const LoginPage(),
      ),
    );
  }
}

class MainNavigation extends StatelessWidget {
  const MainNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.map), label: 'Radar'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.list_bullet), label: 'Leads'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.person), label: 'Perfil'),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) {
            switch (index) {
              case 0:
                return const RadarPage();
              case 1:
                return CupertinoPageScaffold(
                  navigationBar: const CupertinoNavigationBar(middle: Text('Meus Leads')),
                  child: const Center(child: Text('Lista de Leads em breve...')),
                );
              case 2:
                return CupertinoPageScaffold(
                  navigationBar: const CupertinoNavigationBar(
                        middle: Text('Perfil'),
                      ),
                      child: SafeArea(
                        child: Center(
                          child: Consumer(
                            builder: (context, ref, _) => CupertinoButton(
                              color: CupertinoColors.destructiveRed,
                              onPressed: () async {
                                await ref
                                    .read(authControllerProvider)
                                    .signOut();
                              },
                              child: const Text('Sair da conta'),
                            ),
                          ),
                        ),
                      ),
                    );
              default:
                return const CupertinoPageScaffold(child: SizedBox.shrink());
            }
          },
        );
      },
    );
  }
}