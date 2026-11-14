import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/analytics_service.dart';
import 'firebase_options.dart';
import 'features/auth/login_page.dart';
import 'features/auth/profile_page.dart';
import 'features/leads/leads_page.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/groups/presentation/groups_home_page.dart';
import 'features/groups/presentation/organization_gate.dart';
import 'features/groups/providers/group_provider.dart';
import 'features/map/radar_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (!kIsWeb) {
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  runZonedGuarded(
    () => runApp(const ProviderScope(child: RumoApp())),
    (error, stack) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
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
        data: (user) {
          if (user != null) {
            // sem organização, só Perfil e Organização (sem mapa nem busca)
            return const OrganizationGate(child: MainNavigation());
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

enum _Tab {
  radar('Radar', CupertinoIcons.map),
  leads('Leads', CupertinoIcons.list_bullet),
  perfil('Perfil', CupertinoIcons.person),
  organizacao('Organização', CupertinoIcons.building_2_fill);

  const _Tab(this.label, this.icon);
  final String label;
  final IconData icon;
}

List<_Tab> _tabsFor({required bool hasOrganization}) =>
    hasOrganization ? _Tab.values : const [_Tab.organizacao, _Tab.perfil];

/// Rótulos das abas pra quem tem (ou não) organização.
@visibleForTesting
List<String> mainTabLabels({required bool hasOrganization}) =>
    [for (final t in _tabsFor(hasOrganization: hasOrganization)) t.label];

/// Abas do app. Radar e Leads (a carteira de clientes) só existem pra quem
/// pertence a uma organização; sem ela o usuário só tem Perfil e Organização
/// (onde cria uma ou entra com um código de convite).
class MainNavigation extends ConsumerWidget {
  const MainNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasOrganization =
        (ref.watch(myGroupsProvider).valueOrNull ?? const []).isNotEmpty;
    final tabs =
        hasOrganization ? _Tab.values : const [_Tab.organizacao, _Tab.perfil];

    return CupertinoTabScaffold(
      // trocar o conjunto de abas recria o scaffold (o índice não vale mais)
      key: ValueKey(hasOrganization),
      tabBar: CupertinoTabBar(
        onTap: (index) {
          ref.read(analyticsProvider).logScreenView(
                screenName: tabs[index].label,
              );
        },
        items: [
          for (final t in tabs)
            BottomNavigationBarItem(icon: Icon(t.icon), label: t.label),
        ],
      ),
      tabBuilder: (context, index) {
        return CupertinoTabView(
          builder: (context) {
            switch (tabs[index]) {
              case _Tab.radar:
                return const RadarPage();
              case _Tab.leads:
                return const LeadsPage();
              case _Tab.perfil:
                return const ProfilePage();
              case _Tab.organizacao:
                return const GroupsHomePage();
            }
          },
        );
      },
    );
  }
}
