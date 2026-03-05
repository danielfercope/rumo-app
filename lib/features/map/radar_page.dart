import 'package:flutter/cupertino.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Import do Riverpod
import 'providers/location_provider.dart'; // Import do seu Provider

// 1. Troque StatefulWidget por ConsumerStatefulWidget
class RadarPage extends ConsumerStatefulWidget {
  const RadarPage({super.key});

  @override
  ConsumerState<RadarPage> createState() => _RadarPageState();
}

// 2. Troque State por ConsumerState
class _RadarPageState extends ConsumerState<RadarPage> {
  late GoogleMapController mapController;
  MapType _currentMapType = MapType.normal;

  final LatLng _center = const LatLng(-26.4843, -49.0717); // Jaraguá do Sul

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _toggleMapType() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal
          ? MapType.hybrid : MapType.normal;
    });
  }

  // Função nova: Centraliza a câmera usando o Riverpod
  Future<void> _centerOnUser() async {
    // Lê o provider. Isso vai disparar o pedido de permissão do iOS/Android!
    final positionAsync = await ref.read(locationProvider.future);

    if (positionAsync != null) {
      // Anima a câmera do Google Maps para a posição do vendedor
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(positionAsync.latitude, positionAsync.longitude),
            zoom: 16.0, // Zoom mais próximo
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _center,
              zoom: 14.0,
            ),
            mapType: _currentMapType,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
          ),
          Positioned(
            top: 60,
            right: 16,
            child: CupertinoButton(
              padding: const EdgeInsets.all(12),
              color: CupertinoColors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(30),
              onPressed: _toggleMapType,
              child: const Icon(CupertinoIcons.layers_alt, color: CupertinoColors.activeBlue),
            ),
          ),

          // 3. Atualizamos o botão de GPS
          Positioned(
            bottom: 30,
            right: 16,
            child: CupertinoButton(
              padding: const EdgeInsets.all(12),
              color: CupertinoColors.activeBlue,
              borderRadius: BorderRadius.circular(30),
              onPressed: _centerOnUser, // Chama a função que move o mapa
              child: const Icon(CupertinoIcons.location_fill, color: CupertinoColors.white),
            ),
          ),
        ],
      ),
    );
  }
}