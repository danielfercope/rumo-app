import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/services/analytics_service.dart';
import 'core/services/api_client.dart';
import 'core/services/client_error_reporter.dart';
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

  final container = ProviderContainer();

  // Android/iOS: Crashlytics. Web (sem Crashlytics): o erro vai pro log do
  // Backend (/backend/client-errors → CloudWatch em produção).
  final void Function(Object, StackTrace?, {bool fatal}) recordError;
  if (kIsWeb) {
    final reporter = ClientErrorReporter(
      container.read(apiClientProvider),
      // só o caminho: query/fragmento podem carregar dado que não deve ir pro log
      currentUrl: () => Uri.base.path,
    );
    recordError = (error, stack, {fatal = false}) {
      // erro de zona/plataforma não passa pelo presentError: mantém no console
      if (fatal) debugPrint('$error\n$stack');
      reporter.report(error, stack, fatal: fatal);
    };
    FlutterError.onError = (details) {
      FlutterError.presentError(details); // continua no console do navegador
      recordError(details.exception, details.stack, fatal: false);
    };
  } else {
    recordError = (error, stack, {fatal = false}) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
    };
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  }
  PlatformDispatcher.instance.onError = (error, stack) {
    recordError(error, stack, fatal: true);
    return true;
  };

  runZonedGuarded(
    () => runApp(UncontrolledProviderScope(
      container: container,
      child: const RumoApp(),
    )),
    (error, stack) => recordError(error, stack, fatal: true),
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

List<_Tab> _tabsFor({required bool canUseApp}) =>
    canUseApp ? _Tab.values : const [_Tab.organizacao, _Tab.perfil];

/// Rótulos das abas pra quem pode (ou não) usar o app.
@visibleForTesting
List<String> mainTabLabels({required bool canUseApp}) =>
    [for (final t in _tabsFor(canUseApp: canUseApp)) t.label];

/// Abas do app. Radar e Leads (a carteira de clientes) só existem pra quem
/// está numa organização com CRM conectado — não há conta nem base global.
/// Sem isso o usuário só tem Perfil e Organização (onde cria uma, entra com um
/// código de convite ou, sendo admin, conecta o CRM).
class MainNavigation extends ConsumerWidget {
  const MainNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCrm = ref.watch(activeGroupHasCrmProvider);
    if (hasCrm.isLoading && !hasCrm.hasValue) {
      return const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    final canUseApp = hasCrm.valueOrNull ?? false;
    final tabs = _tabsFor(canUseApp: canUseApp);

    return CupertinoTabScaffold(
      // trocar o conjunto de abas recria o scaffold (o índice não vale mais)
      key: ValueKey(canUseApp),
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
