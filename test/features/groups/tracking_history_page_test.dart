import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/presentation/tracking_history_page.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';
import 'package:rumo_app/features/map/providers/map_backend_provider.dart';

import '../../helpers/fake_google_maps.dart';

final _day = DateTime(2026, 11, 10);

final _points = [
  TrackingHistoryPoint(
      latitude: -26.30,
      longitude: -48.84,
      capturedAt: DateTime(2026, 11, 10, 9, 5)),
  TrackingHistoryPoint(
      latitude: -26.31,
      longitude: -48.85,
      capturedAt: DateTime(2026, 11, 10, 9, 10)),
];

void main() {
  setUp(FakeGoogleMapsPlatform.install);

  Future<List<DateTime>> pumpPage(
    WidgetTester tester, {
    required List<TrackingHistoryPoint> Function(DateTime day) history,
    bool useGoogle = true,
  }) async {
    final requested = <DateTime>[];
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        useGoogleMapsProvider.overrideWith(() => FixedMapBackend(useGoogle)),
        trackingHistoryProvider.overrideWith((ref, key) async {
          requested.add(key.day);
          return history(key.day);
        }),
      ],
      child: CupertinoApp(
        home: TrackingHistoryPage(
            groupId: 'g1', userId: 'u1', nome: 'Ana', initialDay: _day),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return requested;
  }

  testWidgets('com Google Maps desenha a linha do trajeto e lista horários',
      (tester) async {
    await pumpPage(tester, history: (_) => _points);

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.polylines.single.points.length, 2);
    expect(map.markers.map((m) => m.markerId.value), {'inicio', 'fim'});
    expect(find.text('10/11/2026'), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
    expect(find.text('09:10'), findsOneWidget);
  });

  testWidgets('no fallback OSM desenha a polyline', (tester) async {
    await pumpPage(tester, history: (_) => _points, useGoogle: false);

    expect(find.byType(GoogleMap), findsNothing);
    expect(find.byType(PolylineLayer), findsOneWidget);
  });

  testWidgets('dia sem registros mostra a mensagem', (tester) async {
    await pumpPage(tester, history: (_) => const []);

    expect(find.text('Nenhuma posição registrada neste dia.'), findsOneWidget);
    expect(find.byType(GoogleMap), findsNothing);
  });

  testWidgets('seta pra trás busca o dia anterior', (tester) async {
    final requested = await pumpPage(tester, history: (_) => _points);

    await tester.tap(find.byIcon(CupertinoIcons.chevron_left));
    await tester.pump();
    await tester.pump();

    expect(find.text('09/11/2026'), findsOneWidget);
    expect(requested.last, DateTime(2026, 11, 9));
  });

  testWidgets('hoje não permite avançar', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        useGoogleMapsProvider.overrideWith(() => FixedMapBackend(true)),
        trackingHistoryProvider.overrideWith((ref, key) async => _points),
      ],
      child: const CupertinoApp(
        home: TrackingHistoryPage(groupId: 'g1', userId: 'u1', nome: 'Ana'),
      ),
    ));
    await tester.pump();

    final forward = tester.widget<CupertinoButton>(find.ancestor(
        of: find.byIcon(CupertinoIcons.chevron_right),
        matching: find.byType(CupertinoButton)));
    expect(forward.onPressed, isNull);
  });

  testWidgets('mostra o resumo do dia e a linha do tempo em formato BR',
      (tester) async {
    await pumpPage(tester, history: (_) => _points);

    expect(find.text('terça-feira, 10 de novembro de 2026'), findsOneWidget);
    expect(find.textContaining('2 lugares'), findsOneWidget);
    expect(find.textContaining('das 09:05 às 09:10'), findsOneWidget);
    expect(find.text('Primeiro registro do dia'), findsOneWidget);
    expect(find.text('Último registro'), findsWidgets);
    // coordenadas com vírgula decimal
    expect(find.text('-26,30000, -48,84000'), findsOneWidget);
    expect(find.textContaining('desde o ponto anterior'), findsOneWidget);
  });

  testWidgets('tocar numa entrada marca o ponto selecionado no mapa',
      (tester) async {
    await pumpPage(tester, history: (_) => _points);

    await tester.tap(find.text('09:05'));
    await tester.pump();

    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.markers.map((m) => m.markerId.value), contains('sel'));
  });
}
