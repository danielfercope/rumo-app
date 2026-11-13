import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../core/format/br_format.dart';
import '../../map/providers/map_backend_provider.dart';
import '../../map/widgets/osm_map.dart';
import '../../map/widgets/user_avatar.dart';
import '../models/group_member_model.dart';
import '../providers/group_provider.dart';
import 'tracking_history_page.dart';

/// Mapa com a posição atual dos membros do grupo que estão compartilhando
/// localização, cada um com a foto da conta (ou as iniciais). Tocar num
/// membro abre o histórico de deslocamento dele. Só é navegável por um admin
/// de um grupo com `tracking_enabled = true` (ver group_management_view.dart).
class TeamMapPage extends ConsumerStatefulWidget {
  const TeamMapPage({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<TeamMapPage> createState() => _TeamMapPageState();
}

class _TeamMapPageState extends ConsumerState<TeamMapPage> {
  static const _defaultCenter = LatLng(-26.4843, -49.0717);
  static const _avatarSize = 44.0;

  // Ícones do Google Maps (que só aceita bitmap), por usuário. Enquanto o
  // avatar não fica pronto, o marcador usa o pino padrão.
  final Map<String, BitmapDescriptor> _icons = {};
  final Map<String, String> _iconKeys = {};

  void _openHistory(TrackingPoint p) {
    Navigator.of(context).push(CupertinoPageRoute<void>(
      builder: (_) => TrackingHistoryPage(
          groupId: widget.groupId, userId: p.userId, nome: p.nome),
    ));
  }

  String _snippet(TrackingPoint p) => p.ultimoVisto != null
      ? 'Visto ${formatSinceBr(p.ultimoVisto!)} · toque para ver o histórico'
      : 'Toque para ver o histórico';

  /// Gera (uma vez por foto/nome) o ícone do Google Maps de cada membro.
  Future<void> _prepareIcons(List<TrackingPoint> points) async {
    for (final p in points) {
      final url = p.fotoUrl ?? '';
      final key = '$url|${p.nome}';
      if (_iconKeys[p.userId] == key) continue;
      _iconKeys[p.userId] = key;
      Uint8List? photo;
      if (url.isNotEmpty) {
        photo = await ref.read(memberPhotoProvider(url).future);
      }
      try {
        final png = await renderUserAvatarPng(
            initials: userInitials(p.nome), photo: photo);
        if (!mounted) return;
        setState(() => _icons[p.userId] = BitmapDescriptor.bytes(png,
            width: _avatarSize, height: _avatarSize));
      } catch (_) {
        // fica com o pino padrão
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackingAsync = ref.watch(groupTrackingProvider(widget.groupId));
    final useGoogle = ref.watch(useGoogleMapsProvider);

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Mapa da Equipe'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () =>
              ref.invalidate(groupTrackingProvider(widget.groupId)),
          child: const Icon(CupertinoIcons.refresh),
        ),
      ),
      child: trackingAsync.when(
        data: (points) {
          final initialTarget = points.isNotEmpty
              ? LatLng(points.first.latitude, points.first.longitude)
              : _defaultCenter;
          if (!useGoogle) {
            return OsmMap(
              center:
                  ll.LatLng(initialTarget.latitude, initialTarget.longitude),
              zoom: 12.0,
              markers: [
                for (final p in points)
                  OsmMarkerData(
                    id: p.userId,
                    position: ll.LatLng(p.latitude, p.longitude),
                    title: p.nome,
                    snippet: _snippet(p),
                    onTap: () => _openHistory(p),
                    alignment: Alignment.center,
                    size: _avatarSize,
                    child: _MemberAvatar(point: p, size: _avatarSize),
                  ),
              ],
            );
          }
          _prepareIcons(points);
          return GoogleMap(
            initialCameraPosition:
                CameraPosition(target: initialTarget, zoom: 12.0),
            markers: points
                .map(
                  (p) => Marker(
                    markerId: MarkerId(p.userId),
                    position: LatLng(p.latitude, p.longitude),
                    icon: _icons[p.userId] ?? BitmapDescriptor.defaultMarker,
                    anchor: _icons.containsKey(p.userId)
                        ? const Offset(0.5, 0.5)
                        : const Offset(0.5, 1.0),
                    infoWindow: InfoWindow(
                      title: p.nome,
                      snippet: _snippet(p),
                      onTap: () => _openHistory(p),
                    ),
                  ),
                )
                .toSet(),
          );
        },
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => Center(child: Text('Erro ao carregar a equipe: $e')),
      ),
    );
  }
}

/// Avatar de um membro: a foto da conta, ou as iniciais enquanto carrega/sem foto.
class _MemberAvatar extends ConsumerWidget {
  const _MemberAvatar({required this.point, required this.size});

  final TrackingPoint point;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = point.fotoUrl ?? '';
    final photo =
        url.isEmpty ? null : ref.watch(memberPhotoProvider(url)).valueOrNull;
    return UserAvatar(
      initials: userInitials(point.nome),
      photo: photo,
      size: size,
      borderWidth: 3,
    );
  }
}
