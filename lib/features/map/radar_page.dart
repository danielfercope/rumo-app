import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'providers/location_provider.dart';
import 'providers/company_provider.dart';
import 'providers/filter_provider.dart';
import '../auth/providers/profile_provider.dart';
import 'services/tracking_service.dart';
import 'models/company_model.dart';
import '../company/add_company_modal.dart';
import 'presentation/filter_modal.dart';
import 'presentation/company_details_modal.dart';
import 'presentation/radar_viewmodel.dart';

class RadarPage extends ConsumerStatefulWidget {
  const RadarPage({super.key});

  @override
  ConsumerState<RadarPage> createState() => _RadarPageState();
}

class _RadarPageState extends ConsumerState<RadarPage> {
  late GoogleMapController mapController;
  bool _mapControllerReady = false;
  MapType _currentMapType = MapType.normal;

  DateTime? _lastTapTime;
  String? _lastTappedMarkerId;

  LatLng? _lastCameraPosition;
  bool _pendingAutoFit = false;

  final LatLng _defaultCenter = const LatLng(-26.4843, -49.0717);

  BitmapDescriptor? _iconLibria;
  BitmapDescriptor? _iconSaveId;
  BitmapDescriptor? _iconOtherClient;

  @override
  void initState() {
    super.initState();
    _loadIcons();
    // Esconde a lista após 10 segundos automaticamente
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        ref.read(radarViewModelProvider.notifier).hideBottomList();
      }
    });
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  }

  Future<void> _loadIcons() async {
    const int targetWidth = 35;
    try {
      final Uint8List libriaBytes =
          await _getBytesFromAsset('assets/libria.png', targetWidth);
      final Uint8List saveIdBytes =
          await _getBytesFromAsset('assets/save_id.png', targetWidth);
      final Uint8List otherClientBytes =
          await _getBytesFromAsset('assets/icon_save.webp', targetWidth);

      if (mounted) {
        setState(() {
          _iconLibria = BitmapDescriptor.fromBytes(libriaBytes);
          _iconSaveId = BitmapDescriptor.fromBytes(saveIdBytes);
          _iconOtherClient = BitmapDescriptor.fromBytes(otherClientBytes);
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar ícones: $e');
    }
  }

  BitmapDescriptor _getMarkerIcon(Company company) {
    if (company.isClient == true) {
      if (company.produto == 'Libr.ia') {
        return _iconLibria ??
            BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure);
      } else if (company.produto == 'SaveID') {
        return _iconSaveId ??
            BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure);
      } else {
        return _iconOtherClient ??
            BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure);
      }
    } else {
      return BitmapDescriptor.defaultMarkerWithHue(200.0);
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _mapControllerReady = true;
  }

  void _syncCameraToPosition(LatLng target) {
    if (!_mapControllerReady) return;
    if (_lastCameraPosition == target) return;
    _lastCameraPosition = target;
    mapController.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: target, zoom: 14.0),
    ));
  }

  void _fitToMarkers(List<Company> companies, LatLng? userPos) {
    if (!_mapControllerReady) return;
    final mapped = companies
        .where((c) => c.latitude != null && c.longitude != null)
        .toList();
    if (mapped.isEmpty) return;

    double minLat = mapped.first.latitude!;
    double maxLat = mapped.first.latitude!;
    double minLng = mapped.first.longitude!;
    double maxLng = mapped.first.longitude!;

    for (final c in mapped) {
      if (c.latitude! < minLat) minLat = c.latitude!;
      if (c.latitude! > maxLat) maxLat = c.latitude!;
      if (c.longitude! < minLng) minLng = c.longitude!;
      if (c.longitude! > maxLng) maxLng = c.longitude!;
    }

    if (userPos != null) {
      if (userPos.latitude < minLat) minLat = userPos.latitude;
      if (userPos.latitude > maxLat) maxLat = userPos.latitude;
      if (userPos.longitude < minLng) minLng = userPos.longitude;
      if (userPos.longitude > maxLng) maxLng = userPos.longitude;
    }

    mapController.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.01, minLng - 0.01),
          northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
        ),
        60,
      ),
    );
  }

  void _toggleMapType() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal
          ? MapType.hybrid
          : MapType.normal;
    });
  }

  void _showFilters() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => const FilterModal(),
    );
  }

  void _handleMarkerTap(Company company) {
    final now = DateTime.now();
    if (_lastTappedMarkerId == company.id &&
        _lastTapTime != null &&
        now.difference(_lastTapTime!) <
            const Duration(milliseconds: 500)) {
      _showCompanyDetails(company);
      _lastTapTime = null;
      _lastTappedMarkerId = null;
    } else {
      _lastTapTime = now;
      _lastTappedMarkerId = company.id;
      mapController.showMarkerInfoWindow(MarkerId(company.id));
    }
  }

  void _showCompanyDetails(Company company) {
    showCupertinoModalPopup(
      context: context,
      barrierDismissible: true,
      builder: (context) => CompanyDetailsModal(company: company),
    );
  }

  Future<void> _centerOnUser() async {
    final positionAsync = await ref.read(locationProvider.future);
    mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(positionAsync.latitude, positionAsync.longitude),
          zoom: 16.0,
        ),
      ),
    );
  }

  void _openAddCompany() async {
    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (_) => const AddCompanyModal(),
    );
    if (result == true && mounted) {
      ref.invalidate(companiesProvider);
      _showSuccessToast();
    }
  }

  void _showSuccessToast() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Empresa cadastrada!'),
        content:
            const Text('Os dados foram salvos e enviados ao CRM.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationProvider);
    final companiesAsync = ref.watch(companiesProvider);
    final filters = ref.watch(mapFiltersProvider);
    final profileAsync = ref.watch(profileProvider);
    final uiState = ref.watch(radarViewModelProvider);

    ref.listen<AsyncValue<UserProfile?>>(profileProvider, (_, next) {
      next.whenData((profile) {
        if (profile?.isExecutivo == true) {
          ref.read(trackingServiceProvider).startForUser(profile!);
        }
      });
    });

    ref.listen<MapFilters>(mapFiltersProvider, (_, __) {
      _pendingAutoFit = true;
    });

    return CupertinoPageScaffold(
      child: locationAsync.when(
        data: (position) => companiesAsync.when(
          data: (companies) => _buildContent(
              position, companies, filters.radius, uiState,
              profile: profileAsync.value),
          loading: () =>
              const Center(child: CupertinoActivityIndicator()),
          error: (error, stack) => _buildContent(
              position, [], filters.radius, uiState,
              errorMessage:
                  'Erro ao buscar empresas. Verifique sua conexão.',
              profile: profileAsync.value),
        ),
        loading: () =>
            const Center(child: CupertinoActivityIndicator()),
        error: (error, stack) => companiesAsync.when(
          data: (companies) => _buildContent(
              null, companies, filters.radius, uiState,
              profile: profileAsync.value),
          loading: () =>
              const Center(child: CupertinoActivityIndicator()),
          error: (error, stack) => _buildContent(
              null, [], filters.radius, uiState,
              errorMessage:
                  'Erro ao buscar empresas. Verifique sua conexão.',
              profile: profileAsync.value),
        ),
      ),
    );
  }

  Widget _buildContent(
    Position? position,
    List<Company> companies,
    double radius,
    RadarUiState uiState, {
    String? errorMessage,
    UserProfile? profile,
  }) {
    final initialTarget = position != null
        ? LatLng(position.latitude, position.longitude)
        : _defaultCenter;

    final List<Company> sorted = List.from(companies)
      ..sort((a, b) =>
          (a.distance ?? 999999).compareTo(b.distance ?? 999999));
    final displayCompanies = sorted.take(3).toList();

    final mappableCompanies = sorted
        .where((c) => c.latitude != null && c.longitude != null)
        .toList();

    if (_pendingAutoFit && mappableCompanies.isNotEmpty) {
      _pendingAutoFit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitToMarkers(
            mappableCompanies,
            position != null
                ? LatLng(position.latitude, position.longitude)
                : null);
      });
    } else if (position != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncCameraToPosition(
            LatLng(position.latitude, position.longitude));
      });
    }

    final mappableCount = companies
        .where((c) => c.latitude != null && c.longitude != null)
        .length;

    final bool isListVisible =
        uiState.showBottomList && displayCompanies.isNotEmpty;

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition:
              CameraPosition(target: initialTarget, zoom: 14.0),
          mapType: _currentMapType,
          myLocationEnabled: !kIsWeb,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: {
            ...mappableCompanies.map((company) {
              return Marker(
                markerId: MarkerId(company.id),
                position:
                    LatLng(company.latitude!, company.longitude!),
                consumeTapEvents: true,
                infoWindow: InfoWindow(
                  title:
                      company.fantasyName ?? company.name ?? 'Empresa',
                  snippet: company.segment ??
                      'CNAE: ${company.cnaePrincipal ?? "N/A"}',
                  onTap: () => _showCompanyDetails(company),
                ),
                onTap: () => _handleMarkerTap(company),
                icon: _getMarkerIcon(company),
              );
            }),
            if (kIsWeb && position != null)
              Marker(
                markerId: const MarkerId('__my_location__'),
                position: LatLng(position.latitude, position.longitude),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
                infoWindow: const InfoWindow(title: 'Você está aqui'),
                zIndex: 10,
              ),
          },
          circles: {
            Circle(
              circleId: const CircleId('radius_circle'),
              center: initialTarget,
              radius: radius * 1000,
              fillColor:
                  CupertinoColors.activeBlue.withOpacity(0.05),
              strokeColor:
                  CupertinoColors.activeBlue.withOpacity(0.2),
              strokeWidth: 1,
            ),
          },
        ),

        // Controles: tipo de mapa, filtros, adicionar empresa, contador
        Positioned(
          top: 60,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(12),
                color: CupertinoColors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(30),
                onPressed: _toggleMapType,
                child: const Icon(CupertinoIcons.layers_alt,
                    color: CupertinoColors.activeBlue),
              ),
              const SizedBox(height: 8),
              CupertinoButton(
                padding: const EdgeInsets.all(12),
                color: CupertinoColors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(30),
                onPressed: _showFilters,
                child: const Icon(
                    CupertinoIcons.slider_horizontal_3,
                    color: CupertinoColors.activeBlue),
              ),
              const SizedBox(height: 8),
              if (profile?.canAddCompany == true && position != null)
                CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  color:
                      CupertinoColors.systemYellow.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(30),
                  onPressed: _openAddCompany,
                  child: const Icon(CupertinoIcons.plus,
                      color: CupertinoColors.black),
                ),
              if (profile?.canAddCompany == true && position != null)
                const SizedBox(height: 8),
              GestureDetector(
                onTap: () => ref
                    .read(radarViewModelProvider.notifier)
                    .toggleCountExpanded(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: mappableCount > 0
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.systemOrange,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color:
                            CupertinoColors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    uiState.isCountExpanded
                        ? '$mappableCount no mapa / ${companies.length} total'
                        : mappableCount > 0
                            ? '$mappableCount'
                            : '${companies.length} sem coord.',
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              if (mappableCount > 0) ...[
                const SizedBox(height: 8),
                CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  color: CupertinoColors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  onPressed: () => _fitToMarkers(
                      mappableCompanies,
                      position != null
                          ? LatLng(position.latitude,
                              position.longitude)
                          : null),
                  child: const Icon(CupertinoIcons.map_fill,
                      color: CupertinoColors.activeBlue),
                ),
              ],
            ],
          ),
        ),

        // Botão de localização (inferior esquerdo)
        Positioned(
          bottom: isListVisible ? 240 : 100,
          left: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                padding: const EdgeInsets.all(12),
                color: CupertinoColors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(30),
                onPressed: _centerOnUser,
                child: Icon(
                  position != null
                      ? CupertinoIcons.location_fill
                      : CupertinoIcons.location_slash,
                  color: position != null
                      ? CupertinoColors.activeBlue
                      : CupertinoColors.systemOrange,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: CupertinoColors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  position != null
                      ? '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}'
                      : 'GPS indisponível',
                  style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),

        // Botão para reabrir a lista (inferior direito)
        Positioned(
          bottom: 100,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isListVisible && displayCompanies.isNotEmpty)
                CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  color: CupertinoColors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  onPressed: () => ref
                      .read(radarViewModelProvider.notifier)
                      .showList(),
                  child: const Icon(CupertinoIcons.list_bullet,
                      color: CupertinoColors.activeBlue),
                ),
            ],
          ),
        ),

        if (errorMessage != null)
          Positioned(
            top: 110,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    CupertinoColors.systemRed.withOpacity(0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                errorMessage,
                style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          ),

        // Lista das 3 empresas mais próximas
        if (isListVisible)
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => ref
                      .read(radarViewModelProvider.notifier)
                      .hideBottomList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          CupertinoColors.activeBlue.withOpacity(0.9),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'As 3 empresas mais próximas de você',
                          style: TextStyle(
                            color: CupertinoColors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(CupertinoIcons.chevron_down,
                            color: CupertinoColors.white, size: 12),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: displayCompanies.map((company) {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _showCompanyDetails(company),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 2),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: CupertinoColors.white,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                            boxShadow: [
                              BoxShadow(
                                  color: CupertinoColors.black
                                      .withOpacity(0.1),
                                  blurRadius: 4)
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  company.fantasyName ??
                                      company.name ??
                                      'Empresa',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: CupertinoColors.black),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text(company.segment ?? 'N/A',
                                  style: const TextStyle(
                                      fontSize: 8,
                                      color:
                                          CupertinoColors.activeBlue,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(
                                  '${company.distance?.toStringAsFixed(1)}km',
                                  style: const TextStyle(
                                      fontSize: 9,
                                      color: CupertinoColors.black,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
