import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/presentation/team_map_page.dart';
import 'package:rumo_app/features/groups/presentation/tracking_history_page.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';
import 'package:rumo_app/features/map/providers/map_backend_provider.dart';

import '../../helpers/fake_google_maps.dart';

const _points = [
  TrackingPoint(
    userId: 'u1',
    nome: 'Ana',
    email: 'ana@x.com',
    latitude: -26.30,
    longitude: -48.84,
  ),
  TrackingPoint(
    userId: 'u2',
    nome: 'Beto',
    email: 'beto@x.com',
    latitude: -26.31,
    longitude: -48.85,
  ),
];

void main() {
  setUp(FakeGoogleMapsPlatform.install);

  Future<void> pumpPage(
    WidgetTester tester, {
    required Future<List<TrackingPoint>> Function() tracking,
    bool useGoogle = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        useGoogleMapsProvider.overrideWith(() => FixedMapBackend(useGoogle)),
        groupTrackingProvider('g1').overrideWith((ref) => tracking()),
        trackingHistoryProvider.overrideWith((ref, key) async => const []),
      ],
      child: const CupertinoApp(home: TeamMapPage(groupId: 'g1')),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('mostra o indicador enquanto carrega a equipe', (tester) async {
    await pumpPage(tester,
        tracking: () => Completer<List<TrackingPoint>>().future);

    expect(find.text('Mapa da Equipe'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(find.byType(GoogleMap), findsNothing);
  });

  testWidgets('mostra a mensagem de erro quando a busca falha', (tester) async {
    await pumpPage(tester, tracking: () async => throw 'sem rede');

    expect(find.textContaining('Erro ao carregar a equipe'), findsOneWidget);
  });

  testWidgets('com Google Maps desenha um marcador por membro', (tester) async {
    await pumpPage(tester, tracking: () async => _points);

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.markers.map((m) => m.markerId.value), {'u1', 'u2'});
    expect(map.initialCameraPosition.target, const LatLng(-26.30, -48.84));
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets('sem membros centraliza no ponto padrão', (tester) async {
    await pumpPage(tester, tracking: () async => const []);

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.markers, isEmpty);
    expect(map.initialCameraPosition.target, const LatLng(-26.4843, -49.0717));
  });

  testWidgets('no fallback OSM desenha os membros e tocar abre o histórico',
      (tester) async {
    await pumpPage(tester, tracking: () async => _points, useGoogle: false);

    expect(find.byType(GoogleMap), findsNothing);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length, 2);

    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('u1')),
        matching: find.byType(GestureDetector)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(TrackingHistoryPage), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
  });

  testWidgets('mostra o avatar com as iniciais e a última vez em formato BR',
      (tester) async {
    await pumpPage(
      tester,
      tracking: () async => [
        TrackingPoint(
          userId: 'u1',
          nome: 'Ana Souza',
          email: 'ana@x.com',
          latitude: -26.30,
          longitude: -48.84,
          ultimoVisto: DateTime.now().subtract(const Duration(minutes: 7)),
        ),
      ],
      useGoogle: false,
    );

    expect(find.text('AS'), findsOneWidget);
  });

  testWidgets('o botão de atualizar busca a equipe de novo', (tester) async {
    var calls = 0;
    await pumpPage(tester, tracking: () async {
      calls++;
      return _points;
    });
    expect(calls, 1);

    await tester.tap(find.byIcon(CupertinoIcons.refresh));
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
  });
}
