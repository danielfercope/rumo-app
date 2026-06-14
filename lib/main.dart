import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_config.dart';
import 'features/auth/login_page.dart';
import 'features/leads/leads_page.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/map/radar_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
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
                return const LeadsPage();
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