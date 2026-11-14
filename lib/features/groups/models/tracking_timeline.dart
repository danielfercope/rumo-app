import 'dart:math' as math;

import 'group_member_model.dart';

/// Uma entrada da linha do tempo: um período em que a pessoa ficou no mesmo
/// lugar (vários pontos seguidos a até [kStayRadiusMeters] um do outro) ou um
/// ponto isolado. Como um "commit" do histórico: quando, onde e quanto andou
/// desde a entrada anterior.
class TimelineEntry {
  const TimelineEntry({
    required this.start,
    required this.end,
    required this.latitude,
    required this.longitude,
    required this.pointCount,
    required this.distanceFromPreviousMeters,
  });

  final DateTime start;
  final DateTime end;
  final double latitude;
  final double longitude;
  final int pointCount;

  /// Distância em linha reta desde a entrada anterior; `null` na primeira.
  final double? distanceFromPreviousMeters;

  Duration get stayed => end.difference(start);
}

/// Pontos a menos que isto um do outro contam como "o mesmo lugar".
const kStayRadiusMeters = 100.0;

/// Distância em metros entre duas coordenadas (haversine).
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// Agrupa [points] (em ordem cronológica) em entradas, da mais antiga pra
/// mais recente. A posição de uma entrada é a do primeiro ponto do grupo.
List<TimelineEntry> buildTimeline(List<TrackingHistoryPoint> points) {
  final entries = <TimelineEntry>[];
  TrackingHistoryPoint? anchor;
  var start = DateTime(0);
  var end = DateTime(0);
  var count = 0;
  double? gap;

  void flush() {
    if (anchor == null) return;
    entries.add(TimelineEntry(
      start: start,
      end: end,
      latitude: anchor.latitude,
      longitude: anchor.longitude,
      pointCount: count,
      distanceFromPreviousMeters: gap,
    ));
  }

  for (final p in points) {
    final a = anchor;
    if (a != null &&
        distanceMeters(a.latitude, a.longitude, p.latitude, p.longitude) <=
            kStayRadiusMeters) {
      end = p.capturedAt;
      count++;
      continue;
    }
    final prev = a;
    flush();
    gap = prev == null
        ? null
        : distanceMeters(
            prev.latitude, prev.longitude, p.latitude, p.longitude);
    anchor = p;
    start = p.capturedAt;
    end = p.capturedAt;
    count = 1;
  }
  flush();
  return entries;
}

/// Soma dos trechos entre entradas (distância total percorrida).
double totalDistanceMeters(List<TimelineEntry> entries) =>
    entries.fold(0.0, (sum, e) => sum + (e.distanceFromPreviousMeters ?? 0));
