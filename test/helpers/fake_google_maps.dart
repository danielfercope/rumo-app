import 'package:flutter/services.dart' show PlatformViewCreatedCallback;
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Plataforma de mapa falsa: troca a PlatformView nativa por um `SizedBox` e
/// registra as chamadas de câmera, pra testar telas que usam [GoogleMap].
class FakeGoogleMapsPlatform extends GoogleMapsFlutterPlatform
    with MockPlatformInterfaceMixin {
  final cameraUpdates = <CameraUpdate>[];
  final infoWindowsShown = <MarkerId>[];
  final _created = <int>{};

  static FakeGoogleMapsPlatform install() {
    final fake = FakeGoogleMapsPlatform();
    GoogleMapsFlutterPlatform.instance = fake;
    return fake;
  }

  @override
  Future<void> init(int mapId) async {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    // buildView roda a cada rebuild; a criação da view só acontece uma vez.
    if (_created.add(creationId)) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => onPlatformViewCreated(creationId));
    }
    return const SizedBox.expand(key: ValueKey('fake-google-map'));
  }

  @override
  Future<void> updateMapConfiguration(MapConfiguration configuration,
      {required int mapId}) async {}

  @override
  Future<void> updateMarkers(MarkerUpdates markerUpdates,
      {required int mapId}) async {}

  @override
  Future<void> updateCircles(CircleUpdates circleUpdates,
      {required int mapId}) async {}

  @override
  Future<void> updatePolygons(PolygonUpdates polygonUpdates,
      {required int mapId}) async {}

  @override
  Future<void> updatePolylines(PolylineUpdates polylineUpdates,
      {required int mapId}) async {}

  @override
  Future<void> updateTileOverlays(
      {required Set<TileOverlay> newTileOverlays, required int mapId}) async {}

  @override
  Future<void> updateHeatmaps(HeatmapUpdates heatmapUpdates,
      {required int mapId}) async {}

  @override
  Future<void> updateClusterManagers(ClusterManagerUpdates clusterManagerUpdates,
      {required int mapId}) async {}

  @override
  Future<void> updateGroundOverlays(GroundOverlayUpdates groundOverlayUpdates,
      {required int mapId}) async {}

  @override
  Future<void> animateCamera(CameraUpdate cameraUpdate,
      {required int mapId}) async {
    cameraUpdates.add(cameraUpdate);
  }

  @override
  Future<void> moveCamera(CameraUpdate cameraUpdate,
      {required int mapId}) async {
    cameraUpdates.add(cameraUpdate);
  }

  @override
  Future<void> showMarkerInfoWindow(MarkerId markerId,
      {required int mapId}) async {
    infoWindowsShown.add(markerId);
  }

  @override
  void dispose({required int mapId}) {}

  // Os eventos nativos não existem em teste: todos os streams ficam vazios.
  @override
  Stream<CameraMoveStartedEvent> onCameraMoveStarted({required int mapId}) =>
      const Stream<CameraMoveStartedEvent>.empty();

  @override
  Stream<CameraMoveEvent> onCameraMove({required int mapId}) =>
      const Stream<CameraMoveEvent>.empty();

  @override
  Stream<CameraIdleEvent> onCameraIdle({required int mapId}) =>
      const Stream<CameraIdleEvent>.empty();

  @override
  Stream<MarkerTapEvent> onMarkerTap({required int mapId}) =>
      const Stream<MarkerTapEvent>.empty();

  @override
  Stream<InfoWindowTapEvent> onInfoWindowTap({required int mapId}) =>
      const Stream<InfoWindowTapEvent>.empty();

  @override
  Stream<MarkerDragStartEvent> onMarkerDragStart({required int mapId}) =>
      const Stream<MarkerDragStartEvent>.empty();

  @override
  Stream<MarkerDragEvent> onMarkerDrag({required int mapId}) =>
      const Stream<MarkerDragEvent>.empty();

  @override
  Stream<MarkerDragEndEvent> onMarkerDragEnd({required int mapId}) =>
      const Stream<MarkerDragEndEvent>.empty();

  @override
  Stream<PolylineTapEvent> onPolylineTap({required int mapId}) =>
      const Stream<PolylineTapEvent>.empty();

  @override
  Stream<PolygonTapEvent> onPolygonTap({required int mapId}) =>
      const Stream<PolygonTapEvent>.empty();

  @override
  Stream<CircleTapEvent> onCircleTap({required int mapId}) =>
      const Stream<CircleTapEvent>.empty();

  @override
  Stream<MapTapEvent> onTap({required int mapId}) =>
      const Stream<MapTapEvent>.empty();

  @override
  Stream<MapLongPressEvent> onLongPress({required int mapId}) =>
      const Stream<MapLongPressEvent>.empty();

  @override
  Stream<ClusterTapEvent> onClusterTap({required int mapId}) =>
      const Stream<ClusterTapEvent>.empty();

  @override
  Stream<GroundOverlayTapEvent> onGroundOverlayTap({required int mapId}) =>
      const Stream<GroundOverlayTapEvent>.empty();
}
