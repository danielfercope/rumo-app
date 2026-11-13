import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/tracking_timeline.dart';

TrackingHistoryPoint p(double lat, double lon, int h, int m) =>
    TrackingHistoryPoint(
        latitude: lat,
        longitude: lon,
        capturedAt: DateTime(2026, 11, 10, h, m));

void main() {
  test('haversine: ~1,1 km por 0,01° de latitude', () {
    final d = distanceMeters(-26.30, -48.84, -26.31, -48.84);
    expect(d, closeTo(1112, 5));
  });

  test('pontos no mesmo lugar viram uma entrada com permanência', () {
    final entries = buildTimeline([
      p(-26.3000, -48.8400, 9, 0),
      p(-26.3001, -48.8401, 9, 5),
      p(-26.3000, -48.8399, 9, 10),
    ]);
    expect(entries, hasLength(1));
    expect(entries.single.pointCount, 3);
    expect(entries.single.stayed, const Duration(minutes: 10));
    expect(entries.single.distanceFromPreviousMeters, isNull);
  });

  test('deslocamento gera nova entrada com a distância do trecho', () {
    final entries = buildTimeline([
      p(-26.30, -48.84, 9, 0),
      p(-26.30, -48.84, 9, 5),
      p(-26.31, -48.84, 9, 10),
      p(-26.32, -48.84, 9, 15),
    ]);
    expect(entries, hasLength(3));
    expect(entries[0].pointCount, 2);
    expect(entries[1].distanceFromPreviousMeters, closeTo(1112, 5));
    expect(totalDistanceMeters(entries), closeTo(2224, 10));
  });

  test('voltar a um lugar anterior cria nova entrada (não funde à antiga)', () {
    final entries = buildTimeline([
      p(-26.30, -48.84, 9, 0),
      p(-26.31, -48.84, 9, 10),
      p(-26.30, -48.84, 9, 20),
    ]);
    expect(entries, hasLength(3));
  });

  test('sem pontos, sem entradas', () {
    expect(buildTimeline(const []), isEmpty);
  });
}
