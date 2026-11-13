import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Marcador do [OsmMap]. Sem [onTap], tocar nele abre um alerta com
/// [title]/[snippet] (equivalente ao InfoWindow do Google Maps).
class OsmMarkerData {
  const OsmMarkerData({
    required this.id,
    required this.position,
    required this.child,
    this.title,
    this.snippet,
    this.onTap,
    this.alignment = Alignment.topCenter,
    this.size = 35,
  });

  final String id;
  final LatLng position;
  final Widget child;
  final String? title;
  final String? snippet;
  final VoidCallback? onTap;

  /// `topCenter` faz a ponta de um pin cair na coordenada; use `center` pra
  /// marcadores redondos.
  final Alignment alignment;
  final double size;
}

/// Mapa OpenStreetMap usado quando o Google Maps não está disponível.
class OsmMap extends StatelessWidget {
  const OsmMap({
    super.key,
    required this.center,
    required this.zoom,
    this.controller,
    this.markers = const [],
    this.polylines = const [],
    this.radiusMeters,
    this.onMapReady,
    this.interactive = true,
  });

  final LatLng center;
  final double zoom;
  final MapController? controller;
  final List<OsmMarkerData> markers;

  /// Linhas desenhadas sob os marcadores (ex.: trajeto de um membro).
  final List<Polyline> polylines;

  /// Círculo de raio (em metros) desenhado em volta de [center].
  final double? radiusMeters;
  final VoidCallback? onMapReady;

  /// `false` trava arrastar/zoom (ex.: enquanto um modal está aberto por cima).
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        onMapReady: onMapReady,
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.rumo.rumo_app',
        ),
        if (radiusMeters != null)
          CircleLayer(circles: [
            CircleMarker(
              point: center,
              radius: radiusMeters!,
              useRadiusInMeter: true,
              color: CupertinoColors.activeBlue.withValues(alpha: 0.05),
              borderColor: CupertinoColors.activeBlue.withValues(alpha: 0.2),
              borderStrokeWidth: 1,
            ),
          ]),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(
          markers: [
            for (final m in markers)
              Marker(
                key: ValueKey(m.id),
                point: m.position,
                width: m.size,
                height: m.size,
                alignment: m.alignment,
                child: Builder(
                  builder: (context) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: m.onTap ?? () => _showInfo(context, m),
                    child: m.child,
                  ),
                ),
              ),
          ],
        ),
        // Atribuição exigida pela licença dos dados do OpenStreetMap.
        const SimpleAttributionWidget(
          source: Text('© OpenStreetMap contributors'),
        ),
      ],
    );
  }

  void _showInfo(BuildContext context, OsmMarkerData marker) {
    if (marker.title == null) return;
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(marker.title!),
        content: marker.snippet != null ? Text(marker.snippet!) : null,
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }
}
