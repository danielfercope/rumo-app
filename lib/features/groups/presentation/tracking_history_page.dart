import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/format/br_format.dart';
import '../../map/providers/map_backend_provider.dart';
import '../../map/widgets/osm_map.dart';
import '../models/group_member_model.dart';
import '../models/tracking_timeline.dart';
import '../providers/group_provider.dart';

/// Centro e zoom que enquadram todos os [points] (aproximação por extensão
/// geográfica; não precisa de controller, então vale pros dois mapas).
({double lat, double lon, double zoom}) fitPoints(
    List<TrackingHistoryPoint> points) {
  var minLat = points.first.latitude, maxLat = minLat;
  var minLon = points.first.longitude, maxLon = minLon;
  for (final p in points) {
    minLat = math.min(minLat, p.latitude);
    maxLat = math.max(maxLat, p.latitude);
    minLon = math.min(minLon, p.longitude);
    maxLon = math.max(maxLon, p.longitude);
  }
  final span = math.max(maxLat - minLat, maxLon - minLon);
  final zoom = span < 0.0005
      ? 16.0
      : (math.log(360 / span) / math.ln2 - 1).clamp(4.0, 16.0);
  return (
    lat: (minLat + maxLat) / 2,
    lon: (minLon + maxLon) / 2,
    zoom: zoom.toDouble(),
  );
}

/// Histórico de deslocamento de um membro num dia, no estilo do histórico de
/// commits do GitHub: uma linha do tempo vertical (mais recente primeiro) em
/// que cada entrada é um lugar onde a pessoa esteve, por quanto tempo e
/// quanto andou desde a entrada anterior — mais o trajeto no mapa. Só chega
/// aqui um admin de grupo com rastreamento ligado (a RPC valida no servidor).
class TrackingHistoryPage extends ConsumerStatefulWidget {
  const TrackingHistoryPage({
    super.key,
    required this.groupId,
    required this.userId,
    required this.nome,
    this.initialDay,
  });

  final String groupId;
  final String userId;
  final String nome;
  final DateTime? initialDay;

  @override
  ConsumerState<TrackingHistoryPage> createState() =>
      _TrackingHistoryPageState();
}

class _TrackingHistoryPageState extends ConsumerState<TrackingHistoryPage> {
  late DateTime _day;
  int? _selected; // índice em ordem cronológica
  final _osm = fm.MapController();
  GoogleMapController? _google;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDay ?? DateTime.now();
    _day = DateTime(d.year, d.month, d.day);
  }

  @override
  void dispose() {
    _osm.dispose();
    super.dispose();
  }

  bool get _isToday {
    final n = DateTime.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  void _setDay(DateTime d) => setState(() {
        _day = DateTime(d.year, d.month, d.day);
        _selected = null;
      });

  void _shift(int days) =>
      _setDay(DateTime(_day.year, _day.month, _day.day + days));

  Future<void> _pickDay() async {
    var picked = _day;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 280,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _day,
                maximumDate: DateTime.now(),
                minimumYear: 2024,
                onDateTimeChanged: (d) => picked = d,
              ),
            ),
          ],
        ),
      ),
    );
    if (mounted) _setDay(picked);
  }

  void _select(int index, TimelineEntry entry) {
    setState(() => _selected = index);
    final target = LatLng(entry.latitude, entry.longitude);
    if (ref.read(useGoogleMapsProvider)) {
      _google?.animateCamera(CameraUpdate.newLatLng(target));
    } else {
      try {
        _osm.move(ll.LatLng(entry.latitude, entry.longitude),
            math.max(_osm.camera.zoom, 15));
      } catch (_) {
        // mapa ainda não montou
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (groupId: widget.groupId, userId: widget.userId, day: _day);
    final async = ref.watch(trackingHistoryProvider(key));

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.nome.isEmpty ? 'Histórico' : widget.nome),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => ref.invalidate(trackingHistoryProvider(key)),
          child: const Icon(CupertinoIcons.refresh),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _DayBar(
              day: _day,
              canGoForward: !_isToday,
              onBack: () => _shift(-1),
              onForward: () => _shift(1),
              onPick: _pickDay,
            ),
            Expanded(
              child: async.when(
                data: (points) => points.isEmpty
                    ? const Center(
                        child: Text('Nenhuma posição registrada neste dia.'))
                    : _buildBody(points),
                loading: () =>
                    const Center(child: CupertinoActivityIndicator()),
                error: (e, _) =>
                    Center(child: Text('Erro ao carregar o histórico: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<TrackingHistoryPoint> points) {
    final entries = buildTimeline(points);
    final fit = fitPoints(points);
    final useGoogle = ref.watch(useGoogleMapsProvider);
    final selected = _selected != null && _selected! < entries.length
        ? entries[_selected!]
        : null;
    final first = entries.first;
    final last = entries.last;

    final Widget map;
    if (!useGoogle) {
      map = OsmMap(
        controller: _osm,
        center: ll.LatLng(fit.lat, fit.lon),
        zoom: fit.zoom,
        polylines: [
          fm.Polyline(
            points: [
              for (final p in points) ll.LatLng(p.latitude, p.longitude)
            ],
            strokeWidth: 4,
            color: CupertinoColors.activeBlue,
          ),
        ],
        markers: [
          _osmDot('inicio', first, CupertinoColors.activeGreen, 'Início'),
          if (entries.length > 1)
            _osmDot(
                'fim', last, CupertinoColors.destructiveRed, 'Último registro'),
          if (selected != null)
            _osmDot(
                'sel', selected, CupertinoColors.systemOrange, 'Selecionado',
                size: 26),
        ],
      );
    } else {
      map = GoogleMap(
        onMapCreated: (c) => _google = c,
        initialCameraPosition:
            CameraPosition(target: LatLng(fit.lat, fit.lon), zoom: fit.zoom),
        polylines: {
          Polyline(
            polylineId: const PolylineId('trajeto'),
            points: [for (final p in points) LatLng(p.latitude, p.longitude)],
            width: 4,
            color: CupertinoColors.activeBlue,
          ),
        },
        markers: {
          _googleMarker('inicio', first, BitmapDescriptor.hueGreen, 'Início'),
          if (entries.length > 1)
            _googleMarker(
                'fim', last, BitmapDescriptor.hueRed, 'Último registro'),
          if (selected != null)
            _googleMarker(
                'sel', selected, BitmapDescriptor.hueOrange, 'Selecionado'),
        },
      );
    }

    final total = totalDistanceMeters(entries);
    // Mais recente primeiro, como o histórico de commits.
    final reversed = entries.reversed.toList();

    return Column(
      children: [
        Expanded(flex: 3, child: map),
        _Summary(
          day: _day,
          stops: entries.length,
          distanceMeters: total,
          from: first.start,
          to: last.end,
        ),
        Expanded(
          flex: 3,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: reversed.length,
            itemBuilder: (_, i) {
              final chronological = entries.length - 1 - i;
              final entry = reversed[i];
              return _TimelineTile(
                entry: entry,
                isFirstInDay: chronological == 0,
                isLastInDay: chronological == entries.length - 1,
                isLatest: i == 0,
                selected: _selected == chronological,
                showTopLine: i != 0,
                showBottomLine: i != reversed.length - 1,
                onTap: () => _select(chronological, entry),
              );
            },
          ),
        ),
      ],
    );
  }

  OsmMarkerData _osmDot(String id, TimelineEntry e, Color color, String title,
          {double size = 20}) =>
      OsmMarkerData(
        id: id,
        position: ll.LatLng(e.latitude, e.longitude),
        title: title,
        snippet: formatTimeBr(e.start),
        alignment: Alignment.center,
        size: size,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: CupertinoColors.white, width: 3),
          ),
        ),
      );

  Marker _googleMarker(String id, TimelineEntry e, double hue, String title) =>
      Marker(
        markerId: MarkerId(id),
        position: LatLng(e.latitude, e.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(title: title, snippet: formatTimeBr(e.start)),
      );
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.day,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onPick,
  });

  final DateTime day;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final label = formatDayLabelBr(day);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CupertinoButton(
          onPressed: onBack,
          child: const Icon(CupertinoIcons.chevron_left),
        ),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onPick,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
              if (label == 'Hoje' || label == 'Ontem')
                Text(formatDateBr(day),
                    style: const TextStyle(
                        fontSize: 12, color: CupertinoColors.systemGrey)),
            ],
          ),
        ),
        CupertinoButton(
          onPressed: canGoForward ? onForward : null,
          child: const Icon(CupertinoIcons.chevron_right),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.day,
    required this.stops,
    required this.distanceMeters,
    required this.from,
    required this.to,
  });

  final DateTime day;
  final int stops;
  final double distanceMeters;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoColors.secondaryLabel.resolveFrom(context);
    final placesText = stops == 1 ? '1 lugar' : '$stops lugares';
    return Container(
      width: double.infinity,
      color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatDateLongBr(day),
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '$placesText · ${formatDistanceBr(distanceMeters)} percorridos · '
            'das ${formatTimeBr(from)} às ${formatTimeBr(to)}',
            style: TextStyle(fontSize: 13, color: label),
          ),
        ],
      ),
    );
  }
}

/// Uma entrada da linha do tempo: trilho com a bolinha à esquerda e o cartão
/// com horário, permanência e distância desde a anterior à direita.
class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.entry,
    required this.isFirstInDay,
    required this.isLastInDay,
    required this.isLatest,
    required this.selected,
    required this.showTopLine,
    required this.showBottomLine,
    required this.onTap,
  });

  final TimelineEntry entry;
  final bool isFirstInDay;
  final bool isLastInDay;
  final bool isLatest;
  final bool selected;
  final bool showTopLine;
  final bool showBottomLine;
  final VoidCallback onTap;

  Color get _dotColor => isFirstInDay
      ? CupertinoColors.activeGreen
      : isLastInDay
          ? CupertinoColors.destructiveRed
          : CupertinoColors.systemGrey;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final lineColor = CupertinoColors.systemGrey4.resolveFrom(context);

    final hasRange = entry.pointCount > 1 && entry.stayed.inMinutes >= 1;
    final timeText = hasRange
        ? '${formatTimeBr(entry.start)} – ${formatTimeBr(entry.end)}'
        : formatTimeBr(entry.start);
    final stayText = hasRange
        ? 'Permaneceu ${formatDurationBr(entry.stayed)}'
        : 'Passou por aqui';

    final title = isFirstInDay
        ? 'Primeiro registro do dia'
        : isLastInDay && isLatest
            ? 'Último registro'
            : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Expanded(
                    flex: 1,
                    child: Container(
                        width: 2, color: showTopLine ? lineColor : null),
                  ),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: selected
                              ? CupertinoColors.systemOrange
                              : CupertinoColors.systemBackground
                                  .resolveFrom(context),
                          width: 3),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Container(
                        width: 2, color: showBottomLine ? lineColor : null),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 16, top: 4, bottom: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? CupertinoColors.systemOrange.withValues(alpha: 0.12)
                      : CupertinoColors.secondarySystemBackground
                          .resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(title,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _dotColor)),
                      ),
                    Text(timeText,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(stayText,
                        style: TextStyle(fontSize: 13, color: secondary)),
                    if (entry.distanceFromPreviousMeters != null)
                      Text(
                        '${formatDistanceBr(entry.distanceFromPreviousMeters!)} '
                        'desde o ponto anterior',
                        style: TextStyle(fontSize: 13, color: secondary),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      '${entry.latitude.toStringAsFixed(5).replaceAll('.', ',')}, '
                      '${entry.longitude.toStringAsFixed(5).replaceAll('.', ',')}',
                      style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.tertiaryLabel
                              .resolveFrom(context)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
