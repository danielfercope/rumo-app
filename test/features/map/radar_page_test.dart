import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/auth/providers/profile_provider.dart';
import 'package:rumo_app/features/company/add_company_modal.dart';
import 'package:rumo_app/features/company/crm_service.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/presentation/company_details_modal.dart';
import 'package:rumo_app/features/map/presentation/filter_modal.dart';
import 'package:rumo_app/features/map/providers/company_provider.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';
import 'package:rumo_app/features/map/providers/location_provider.dart';
import 'package:rumo_app/features/map/radar_page.dart';
import 'package:rumo_app/features/map/services/tracking_service.dart';

import '../../helpers/fake_google_maps.dart';
import '../../helpers/fakes.dart';

class MockCrmService extends Mock implements CrmService {}

class MockTrackingService extends Mock implements TrackingService {}

class FakeUserProfile extends Fake implements UserProfile {}

Position _pos() => Position(
      latitude: -26.48,
      longitude: -49.07,
      timestamp: DateTime(2026),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );

UserProfile _profile({String departamento = 'Pré-vendas'}) => UserProfile(
      id: 'u1',
      email: 'u@x.com',
      nome: 'Ana',
      departamento: departamento,
      nivelAcesso: 'user',
    );

void main() {
  late FakeGoogleMapsPlatform maps;
  late FakeCompanyRepository repo;
  late MockCrmService crm;
  late MockTrackingService tracking;

  setUpAll(() => registerFallbackValue(FakeUserProfile()));

  setUp(() {
    maps = FakeGoogleMapsPlatform.install();
    repo = FakeCompanyRepository(
      companies: [
        buildCompany(id: 'a', fantasyName: 'Perto', isClient: false)
          ..distance = 1.0,
        buildCompany(id: 'b', fantasyName: 'Meio', isClient: true)
          ..distance = 2.0,
        buildCompany(id: 'c', fantasyName: 'Longe', isClient: false)
          ..distance = 3.0,
        buildCompany(id: 'd', fantasyName: 'Distante', isClient: false)
          ..distance = 4.0,
      ],
      options: {
        'segments': <String>[],
        'products': <String>[],
        'states': <String>[],
        'cnaes': <String>[],
        'cities': <String>[],
        'stateToCities': <String, dynamic>{},
      },
    );
    crm = MockCrmService();
    when(() => crm.getNotesWithOwners(any())).thenAnswer((_) async => []);
    when(() => crm.getContacts(any())).thenAnswer((_) async => []);
    tracking = MockTrackingService();
    when(() => tracking.startForUser(any())).thenReturn(null);
  });

  Future<ProviderContainer> pumpRadar(
    WidgetTester tester, {
    Future<Position> Function()? location,
    UserProfile? profile,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      companyRepositoryProvider.overrideWithValue(repo),
      locationProvider
          .overrideWith((ref) => location?.call() ?? Future.value(_pos())),
      profileProvider.overrideWith((ref) async => profile),
      crmServiceProvider.overrideWithValue(crm),
      trackingServiceProvider.overrideWithValue(tracking),
      apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://x')),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: RadarPage()),
    ));
    await tester.pump();
    await tester.pump();
    return container;
  }

  /// Desmonta a página e deixa o timer de 10s do `initState` expirar.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  GoogleMap map(WidgetTester tester) =>
      tester.widget<GoogleMap>(find.byType(GoogleMap));

  testWidgets('desenha marcadores, círculo e as 3 empresas mais próximas',
      (tester) async {
    await pumpRadar(tester);

    final g = map(tester);
    expect(g.markers.map((m) => m.markerId.value),
        containsAll(['a', 'b', 'c', 'd']));
    expect(g.circles.single.radius, 5000);
    expect(find.text('As 3 empresas mais próximas de você'), findsOneWidget);
    expect(find.text('Perto'), findsOneWidget);
    expect(find.text('Longe'), findsOneWidget);
    expect(find.text('Distante'), findsNothing);
    expect(find.text('4'), findsOneWidget); // contador de marcadores
    expect(find.text('-26.4800, -49.0700'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('mostra indicador enquanto a localização carrega',
      (tester) async {
    await pumpRadar(tester, location: () => Completer<Position>().future);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(GoogleMap), findsNothing);
    await finish(tester);
  });

  testWidgets('sem GPS ainda mostra o mapa com as empresas', (tester) async {
    await pumpRadar(tester,
        location: () => Future<Position>.error(Exception('sem gps')));
    await tester.pump();
    expect(find.text('GPS indisponível'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.location_slash), findsOneWidget);
    await finish(tester);
  });

  testWidgets('erro ao buscar empresas mostra o aviso', (tester) async {
    repo.error = Exception('rede');
    await pumpRadar(tester);
    await tester.pump();
    expect(find.text('Erro ao buscar empresas. Verifique sua conexão.'),
        findsOneWidget);
    await finish(tester);
  });

  testWidgets('empresas sem coordenadas aparecem como "sem coord."',
      (tester) async {
    repo.companies = [
      buildCompany(id: 'x', latitude: null, longitude: null)..distance = 1,
    ];
    await pumpRadar(tester);
    expect(find.text('1 sem coord.'), findsOneWidget);
    expect(map(tester).markers, isEmpty);
    await finish(tester);
  });

  testWidgets('tocar no contador alterna entre resumo e detalhe',
      (tester) async {
    await pumpRadar(tester);
    await tester.tap(find.text('4'));
    await tester.pump();
    expect(find.text('4 no mapa / 4 total'), findsOneWidget);
    await tester.tap(find.text('4 no mapa / 4 total'));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a lista pode ser ocultada e reaberta', (tester) async {
    await pumpRadar(tester);
    await tester.tap(find.text('As 3 empresas mais próximas de você'));
    await tester.pump();
    expect(find.text('Perto'), findsNothing);

    await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
    await tester.pump();
    expect(find.text('Perto'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a lista some sozinha após 10 segundos', (tester) async {
    await pumpRadar(tester);
    expect(find.text('Perto'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Perto'), findsNothing);
    await finish(tester);
  });

  testWidgets('alterna o tipo de mapa entre normal e híbrido', (tester) async {
    await pumpRadar(tester);
    expect(map(tester).mapType, MapType.normal);
    await tester.tap(find.byIcon(CupertinoIcons.layers_alt));
    await tester.pump();
    expect(map(tester).mapType, MapType.hybrid);
    await tester.tap(find.byIcon(CupertinoIcons.layers_alt));
    await tester.pump();
    expect(map(tester).mapType, MapType.normal);
    await finish(tester);
  });

  testWidgets('botão de filtros abre o FilterModal', (tester) async {
    await pumpRadar(tester);
    await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_3));
    await tester.pumpAndSettle();
    expect(find.byType(FilterModal), findsOneWidget);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('tocar numa empresa da lista abre os detalhes', (tester) async {
    await pumpRadar(tester);
    await tester.tap(find.text('Perto'));
    await tester.pumpAndSettle();
    expect(find.byType(CompanyDetailsModal), findsOneWidget);
    await finish(tester);
  });

  group('marcadores', () {
    testWidgets('um toque mostra o balão; dois toques rápidos abrem detalhes',
        (tester) async {
      await pumpRadar(tester);
      await tester.pump(); // onMapCreated
      final marker =
          map(tester).markers.firstWhere((m) => m.markerId.value == 'a');

      marker.onTap!();
      await tester.pump();
      expect(maps.infoWindowsShown.single.value, 'a');
      expect(find.byType(CompanyDetailsModal), findsNothing);

      marker.onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(CompanyDetailsModal), findsOneWidget);
      await finish(tester);
    });

    testWidgets('toque no balão abre os detalhes', (tester) async {
      await pumpRadar(tester);
      final marker =
          map(tester).markers.firstWhere((m) => m.markerId.value == 'b');
      marker.infoWindow.onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(CompanyDetailsModal), findsOneWidget);
      await finish(tester);
    });

    testWidgets('toques em marcadores diferentes não abrem detalhes',
        (tester) async {
      await pumpRadar(tester);
      await tester.pump();
      final markers = map(tester).markers.toList();
      markers.firstWhere((m) => m.markerId.value == 'a').onTap!();
      markers.firstWhere((m) => m.markerId.value == 'b').onTap!();
      await tester.pump();
      expect(find.byType(CompanyDetailsModal), findsNothing);
      expect(maps.infoWindowsShown, hasLength(2));
      await finish(tester);
    });
  });

  group('câmera', () {
    testWidgets('centralizar na posição do usuário anima a câmera',
        (tester) async {
      await pumpRadar(tester);
      await tester.pump();
      maps.cameraUpdates.clear();
      await tester.tap(find.byIcon(CupertinoIcons.location_fill));
      await tester.pump();
      expect(maps.cameraUpdates, hasLength(1));
      await finish(tester);
    });

    testWidgets('"ajustar aos marcadores" anima a câmera', (tester) async {
      await pumpRadar(tester);
      await tester.pump();
      maps.cameraUpdates.clear();
      await tester.tap(find.byIcon(CupertinoIcons.map_fill));
      await tester.pump();
      expect(maps.cameraUpdates, hasLength(1));
      await finish(tester);
    });
  });

  testWidgets(
      'mudar um filtro reenquadra os marcadores no mapa recriado, sem usar '
      'o controller antigo', (tester) async {
    final container = await pumpRadar(tester);
    await tester.pump();
    maps.cameraUpdates.clear();

    container.read(mapFiltersProvider.notifier).setSegment('Varejo');
    // O mapa sai da árvore durante o reload e é recriado com os novos dados.
    await tester.pump();
    expect(find.byType(GoogleMap), findsNothing);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byType(GoogleMap), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(maps.cameraUpdates, isNotEmpty);
    await finish(tester);
  });

  group('perfil', () {
    testWidgets('quem pode cadastrar vê o botão de adicionar empresa',
        (tester) async {
      await pumpRadar(tester, profile: _profile());
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.plus), findsOneWidget);
      await finish(tester);
    });

    testWidgets('sem permissão não há botão de adicionar', (tester) async {
      await pumpRadar(tester, profile: _profile(departamento: 'Vendas'));
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.plus), findsNothing);
      await finish(tester);
    });

    testWidgets('adicionar empresa abre o modal; cancelar não mostra aviso',
        (tester) async {
      await pumpRadar(tester, profile: _profile());
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.plus));
      await tester.pumpAndSettle();
      expect(find.byType(AddCompanyModal), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
      await tester.pumpAndSettle();
      expect(find.text('Empresa cadastrada!'), findsNothing);
      await finish(tester);
    });

    testWidgets('cadastro concluído mostra o aviso de sucesso',
        (tester) async {
      await pumpRadar(tester, profile: _profile());
      await tester.pump();
      await tester.tap(find.byIcon(CupertinoIcons.plus));
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.byType(AddCompanyModal))).pop(true);
      await tester.pumpAndSettle();
      expect(find.text('Empresa cadastrada!'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Empresa cadastrada!'), findsNothing);
      await finish(tester);
    });

    testWidgets('executivo inicia o rastreamento', (tester) async {
      await pumpRadar(tester, profile: _profile(departamento: 'Executivo'));
      await tester.pump();
      verify(() => tracking.startForUser(any())).called(1);
      await finish(tester);
    });

    testWidgets('não executivo não inicia o rastreamento', (tester) async {
      await pumpRadar(tester, profile: _profile());
      await tester.pump();
      verifyNever(() => tracking.startForUser(any()));
      await finish(tester);
    });
  });

  testWidgets('localização com erro e empresas em erro mostram o aviso',
      (tester) async {
    repo.error = Exception('rede');
    await pumpRadar(tester,
        location: () => Future<Position>.error(Exception('sem gps')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Erro ao buscar empresas. Verifique sua conexão.'),
        findsOneWidget);
    await finish(tester);
  });

  testWidgets('modelo Company usado no teste mantém a distância',
      (tester) async {
    final Company c = buildCompany()..distance = 2.5;
    expect(c.distance, 2.5);
  });
}
