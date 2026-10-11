import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_config.dart';
import 'core/services/analytics_service.dart';
import 'firebase_options.dart';
import 'features/auth/login_page.dart';
import 'features/auth/privacy_policy_page.dart';
import 'features/leads/leads_page.dart';
import 'features/auth/providers/auth_provider.dart';
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

  // TODO(migração Supabase→PostgREST, semana 4): remover depois que
  // company_service/tracking_service/registration_service/hubspot_service
  // pararem de depender do Supabase.instance.client. Login/auth já usa
  // Firebase Auth (ver auth_provider.dart) — isto fica só pelos dados.
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

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

const _tabScreenNames = ['Radar', 'Leads', 'Perfil'];

class MainNavigation extends ConsumerWidget {
  const MainNavigation({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        onTap: (index) {
          ref.read(analyticsProvider).logScreenView(
                screenName: _tabScreenNames[index],
              );
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.map), label: 'Radar'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.list_bullet), label: 'Leads'),
          BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.person), label: 'Perfil'),
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoButton(
                            onPressed: () => Navigator.push(
                              context,
                              CupertinoPageRoute(
                                  builder: (_) => const PrivacyPolicyPage()),
                            ),
                            child: const Text('Política de Privacidade'),
                          ),
                          Consumer(
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
                        ],
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
