import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../providers/group_provider.dart';

/// Mapa com a posição atual dos membros do grupo que estão compartilhando
/// localização. Só é navegável por um admin de um grupo com
/// `tracking_enabled = true` (ver group_management_view.dart).
class TeamMapPage extends ConsumerWidget {
  const TeamMapPage({super.key, required this.groupId});

  final String groupId;

  static const _defaultCenter = LatLng(-26.4843, -49.0717);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingAsync = ref.watch(groupTrackingProvider(groupId));

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Mapa da Equipe'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => ref.invalidate(groupTrackingProvider(groupId)),
          child: const Icon(CupertinoIcons.refresh),
        ),
      ),
      child: trackingAsync.when(
        data: (points) {
          final initialTarget = points.isNotEmpty
              ? LatLng(points.first.latitude, points.first.longitude)
              : _defaultCenter;
          return GoogleMap(
            initialCameraPosition:
                CameraPosition(target: initialTarget, zoom: 12.0),
            markers: points
                .map(
                  (p) => Marker(
                    markerId: MarkerId(p.userId),
                    position: LatLng(p.latitude, p.longitude),
                    infoWindow: InfoWindow(
                      title: p.nome,
                      snippet: p.ultimoVisto != null
                          ? 'Visto por último: ${p.ultimoVisto}'
                          : null,
                    ),
                  ),
                )
                .toSet(),
          );
        },
        loading: () =>
            const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar a equipe: $e')),
      ),
    );
  }
}
