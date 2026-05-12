import 'package:flutter/cupertino.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'providers/location_provider.dart';
import 'providers/company_provider.dart';
import 'providers/filter_provider.dart';
import 'providers/profile_provider.dart';
import 'services/tracking_service.dart';
import 'models/company_model.dart';
import '../company/add_company_modal.dart';
import '../company/hubspot_service.dart';
import 'package:url_launcher/url_launcher.dart';

class RadarPage extends ConsumerStatefulWidget {
  const RadarPage({super.key});

  @override
  ConsumerState<RadarPage> createState() => _RadarPageState();
}

class _RadarPageState extends ConsumerState<RadarPage> {
  late GoogleMapController mapController;
  bool _mapControllerReady = false;
  MapType _currentMapType = MapType.normal;
  bool _showBottomList = true;
  bool _isCountExpanded = false;

  DateTime? _lastTapTime;
  String? _lastTappedMarkerId;

  // Rastreia última posição GPS para mover câmera quando mudar
  LatLng? _lastCameraPosition;

  // Sinaliza que ao próximo carregamento de empresas deve fazer auto-fit
  bool _pendingAutoFit = false;

  final LatLng _defaultCenter = const LatLng(-26.4843, -49.0717);

  BitmapDescriptor? _iconLibria;
  BitmapDescriptor? _iconSaveId;
  BitmapDescriptor? _iconOtherClient;

  @override
  void initState() {
    super.initState();
    _loadIcons();
    _startHideTimer();
  }

  void _startHideTimer() {
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showBottomList = false;
        });
      }
    });
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  Future<void> _loadIcons() async {
    const int targetWidth = 100;
    try {
      final Uint8List libriaBytes = await _getBytesFromAsset('assets/libria.png', targetWidth);
      final Uint8List saveIdBytes = await _getBytesFromAsset('assets/save_id.png', targetWidth);
      final Uint8List otherClientBytes = await _getBytesFromAsset('assets/icon_save.webp', targetWidth);

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
        return _iconLibria ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      } else if (company.produto == 'SaveID') {
        return _iconSaveId ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      } else {
        return _iconOtherClient ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
      }
    } else {
      return BitmapDescriptor.defaultMarkerWithHue(200.0);
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _mapControllerReady = true;
  }

  // Move câmera para a posição GPS quando ela resolve (evita ficar preso no default SC)
  void _syncCameraToPosition(LatLng target) {
    if (!_mapControllerReady) return;
    if (_lastCameraPosition == target) return;
    _lastCameraPosition = target;
    mapController.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: target, zoom: 14.0),
    ));
  }

  // Auto-fit para mostrar todos os marcadores visíveis
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
          ? MapType.hybrid : MapType.normal;
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
        now.difference(_lastTapTime!) < const Duration(milliseconds: 500)) {
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
    if (positionAsync != null) {
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(positionAsync.latitude, positionAsync.longitude),
            zoom: 16.0,
          ),
        ),
      );
    }
  }

  void _openAddCompany() async {
    final result = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (_) => const AddCompanyModal(),
    );
    if (result == true && mounted) {
      // Invalida o cache de empresas para refletir o novo cadastro
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
        content: const Text('Os dados foram salvos e enviados ao CRM.'),
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

    // Inicia tracking automaticamente para Executivos
    ref.listen<AsyncValue<UserProfile?>>(profileProvider, (_, next) {
      next.whenData((profile) {
        if (profile?.isExecutivo == true) {
          ref.read(trackingServiceProvider).startForUser(profile!);
        }
      });
    });

    // Ao mudar filtros, agenda auto-fit quando as empresas recarregarem
    ref.listen<MapFilters>(mapFiltersProvider, (_, __) {
      _pendingAutoFit = true;
    });

    return CupertinoPageScaffold(
      child: locationAsync.when(
        data: (position) => companiesAsync.when(
          data: (companies) => _buildContent(position, companies, filters.radius, profile: profileAsync.value),
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (error, stack) => _buildContent(position, [], filters.radius, errorMessage: 'Erro ao buscar empresas. Verifique sua conexão.', profile: profileAsync.value),
        ),
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (error, stack) => companiesAsync.when(
          data: (companies) => _buildContent(null, companies, filters.radius, profile: profileAsync.value),
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (error, stack) => _buildContent(null, [], filters.radius, errorMessage: 'Erro ao buscar empresas. Verifique sua conexão.', profile: profileAsync.value),
        ),
      ),
    );
  }

  Widget _buildContent(Position? position, List<Company> companies, double radius, {String? errorMessage, UserProfile? profile}) {
    final initialTarget = position != null
        ? LatLng(position.latitude, position.longitude)
        : _defaultCenter;

    final List<Company> sorted = List.from(companies)
      ..sort((a, b) => (a.distance ?? 999999).compareTo(b.distance ?? 999999));
    final displayCompanies = sorted.take(3).toList();

    // Apenas empresas com coordenadas aparecem no mapa
    final mappableCompanies = sorted
        .where((c) => c.latitude != null && c.longitude != null)
        .toList();

    // Auto-fit após mudança de filtros, ou sincronizar câmera para o GPS na primeira carga
    if (_pendingAutoFit && mappableCompanies.isNotEmpty) {
      _pendingAutoFit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitToMarkers(mappableCompanies, position != null ? LatLng(position.latitude, position.longitude) : null);
      });
    } else if (position != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncCameraToPosition(LatLng(position.latitude, position.longitude));
      });
    }
    final mappableCount = companies
        .where((c) => c.latitude != null && c.longitude != null)
        .length;

    final bool isListVisible = _showBottomList && displayCompanies.isNotEmpty;

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: CameraPosition(target: initialTarget, zoom: 14.0),
          mapType: _currentMapType,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: mappableCompanies
              .map((company) {
            return Marker(
              markerId: MarkerId(company.id),
              position: LatLng(company.latitude!, company.longitude!),
              consumeTapEvents: true,
              infoWindow: InfoWindow(
                title: company.fantasyName ?? company.name ?? 'Empresa',
                snippet: company.segment ?? 'CNAE: ${company.cnaePrincipal ?? "N/A"}',
                onTap: () => _showCompanyDetails(company),
              ),
              onTap: () => _handleMarkerTap(company),
              icon: _getMarkerIcon(company),
            );
          }).toSet(),
          circles: {
            Circle(
              circleId: const CircleId('radius_circle'),
              center: initialTarget,
              radius: radius * 1000,
              fillColor: CupertinoColors.activeBlue.withOpacity(0.05),
              strokeColor: CupertinoColors.activeBlue.withOpacity(0.2),
              strokeWidth: 1,
            ),
          },
        ),
        
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
                child: const Icon(CupertinoIcons.layers_alt, color: CupertinoColors.activeBlue),
              ),
              const SizedBox(height: 8),
              CupertinoButton(
                padding: const EdgeInsets.all(12),
                color: CupertinoColors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(30),
                onPressed: _showFilters,
                child: const Icon(CupertinoIcons.slider_horizontal_3, color: CupertinoColors.activeBlue),
              ),
              const SizedBox(height: 8),
              if (profile?.canAddCompany == true && position != null)
                CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  color: CupertinoColors.systemYellow.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(30),
                  onPressed: _openAddCompany,
                  child: const Icon(CupertinoIcons.plus, color: CupertinoColors.black),
                ),
              if (profile?.canAddCompany == true && position != null)
                const SizedBox(height: 8),
              // Contador: empresas com localização / total
              GestureDetector(
                onTap: () => setState(() => _isCountExpanded = !_isCountExpanded),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: mappableCount > 0
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.systemOrange,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    _isCountExpanded
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
              // Botão auto-fit: centraliza câmera nos marcadores visíveis
              if (mappableCount > 0) ...[
                const SizedBox(height: 8),
                CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  color: CupertinoColors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  onPressed: () => _fitToMarkers(
                      mappableCompanies, position != null ? LatLng(position.latitude, position.longitude) : null),
                  child: const Icon(CupertinoIcons.map_fill,
                      color: CupertinoColors.activeBlue),
                ),
              ],
            ],
          ),
        ),

        // Botão de Localização + debug GPS (Inferior Esquerdo)
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
                  position != null ? CupertinoIcons.location_fill : CupertinoIcons.location_slash,
                  color: position != null ? CupertinoColors.activeBlue : CupertinoColors.systemOrange,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

        // Botão para reabrir a lista (Inferior Direito)
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
                  onPressed: () => setState(() => _showBottomList = true),
                  child: const Icon(CupertinoIcons.list_bullet, color: CupertinoColors.activeBlue),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed.withOpacity(0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                errorMessage,
                style: const TextStyle(color: CupertinoColors.white, fontSize: 13, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          ),

        if (isListVisible)
          Positioned(
            bottom: 100, // Elevado para não ficar sob a TabBar
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showBottomList = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: CupertinoColors.activeBlue.withOpacity(0.9),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
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
                        Icon(CupertinoIcons.chevron_down, color: CupertinoColors.white, size: 12),
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
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: CupertinoColors.white,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                            boxShadow: [BoxShadow(color: CupertinoColors.black.withOpacity(0.1), blurRadius: 4)],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(company.fantasyName ?? company.name ?? 'Empresa', 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: CupertinoColors.black), 
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(company.segment ?? 'N/A', 
                                style: const TextStyle(fontSize: 8, color: CupertinoColors.activeBlue, fontWeight: FontWeight.w500), 
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text('${company.distance?.toStringAsFixed(1)}km', 
                                style: const TextStyle(fontSize: 9, color: CupertinoColors.black, fontWeight: FontWeight.bold)),
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

class FilterModal extends ConsumerStatefulWidget {
  const FilterModal({super.key});

  @override
  ConsumerState<FilterModal> createState() => _FilterModalState();
}

class _FilterModalState extends ConsumerState<FilterModal> {
  late MapFilters _tempFilters;

  @override
  void initState() {
    super.initState();
    _tempFilters = ref.read(mapFiltersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final optionsAsync = ref.watch(filterOptionsProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: CupertinoColors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Filtros Avançados', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: CupertinoColors.white)),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  ref.read(mapFiltersProvider.notifier).state = _tempFilters;
                  Navigator.pop(context);
                },
                child: const Text('Aplicar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: optionsAsync.when(
              data: (options) {
                // Correção do erro de sintaxe e lógica de filtragem de cidades
                final List<String> citiesForState;
                if (_tempFilters.state != null) {
                  final stateToCities = options['stateToCities'] as Map<String, dynamic>?;
                  final cities = stateToCities?[_tempFilters.state] as List<dynamic>?;
                  citiesForState = cities?.cast<String>() ?? [];
                } else {
                  citiesForState = (options['cities'] as List? ?? []).cast<String>();
                }

                return ListView(
                  children: [
                    _buildRadiusSection(),
                    const SizedBox(height: 24),
                    _buildSearchableField('Segmento', _tempFilters.segment, (options['segments'] as List? ?? []).cast<String>(), (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(segment: v, clearSegment: v == null));
                    }),
                    _buildSearchableField('Produto', _tempFilters.product, (options['products'] as List? ?? []).cast<String>(), (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(product: v, clearProduct: v == null));
                    }),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Tipo de Empresa', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: CupertinoColors.systemGrey)),
                    ),
                    CupertinoSlidingSegmentedControl<String>(
                      backgroundColor: CupertinoColors.darkBackgroundGray,
                      thumbColor: CupertinoColors.activeBlue,
                      groupValue: _tempFilters.type ?? 'all',
                      children: {
                        'all': _segmentedText('Todos', _tempFilters.type == null),
                        'client': _segmentedText('Cliente', _tempFilters.type == 'client'),
                        'lead': _segmentedText('Lead', _tempFilters.type == 'lead'),
                      },
                      onValueChanged: (v) {
                        setState(() => _tempFilters = _tempFilters.copyWith(type: v == 'all' ? null : v, clearType: v == 'all'));
                      },
                    ),
                    _buildSearchableField('Estado (UF)', _tempFilters.state, (options['states'] as List? ?? []).cast<String>(), (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(state: v, clearState: v == null));
                    }),
                    _buildSearchableField('Cidade', _tempFilters.city, citiesForState, (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(city: v, clearCity: v == null));
                    }),
                    _buildSearchableField('CNAE', _tempFilters.cnae, (options['cnaes'] as List? ?? []).cast<String>(), (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(cnae: v, clearCnae: v == null));
                    }),
                    const SizedBox(height: 40),
                    CupertinoButton(
                      color: CupertinoColors.systemRed.withOpacity(0.2),
                      onPressed: () {
                        setState(() => _tempFilters = MapFilters());
                      },
                      child: const Text('Limpar Todos', style: TextStyle(color: CupertinoColors.systemRed, fontWeight: FontWeight.w600)),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CupertinoActivityIndicator(color: CupertinoColors.white)),
              error: (e, s) => const Center(child: Text('Erro ao carregar opções', style: TextStyle(color: CupertinoColors.white))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Raio de Destaque no Mapa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: CupertinoColors.white)),
            Text('${_tempFilters.radius.toInt()} km', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: CupertinoColors.activeBlue)),
          ],
        ),
        const SizedBox(height: 8),
        CupertinoSlider(
          value: _tempFilters.radius,
          min: 1,
          max: 15000,
          onChanged: (v) => setState(() => _tempFilters = _tempFilters.copyWith(radius: v)),
        ),
      ],
    );
  }

  Widget _segmentedText(String text, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: TextStyle(fontSize: 13, color: isSelected ? CupertinoColors.white : CupertinoColors.systemGrey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
    );
  }

  Widget _buildSearchableField(String label, String? currentValue, List<String> options, Function(String?) onSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: CupertinoColors.systemGrey)),
        ),
        GestureDetector(
          onTap: () => _showSearchPicker(label, options, onSelected),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: CupertinoColors.darkBackgroundGray,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CupertinoColors.systemGrey.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    currentValue ?? 'Selecione...',
                    style: TextStyle(
                      color: currentValue == null ? CupertinoColors.systemGrey2 : CupertinoColors.white,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (currentValue != null)
                  GestureDetector(
                    onTap: () => onSelected(null),
                    child: const Icon(CupertinoIcons.clear_circled_solid, size: 20, color: CupertinoColors.systemGrey),
                  )
                else
                  const Icon(CupertinoIcons.chevron_down, size: 16, color: CupertinoColors.systemGrey2),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSearchPicker(String title, List<String> options, Function(String?) onSelected) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => SearchSelectionSheet(
        title: title,
        options: options,
        onSelected: onSelected,
      ),
    );
  }
}

class SearchSelectionSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final Function(String?) onSelected;

  const SearchSelectionSheet({
    super.key,
    required this.title,
    required this.options,
    required this.onSelected,
  });

  @override
  State<SearchSelectionSheet> createState() => _SearchSelectionSheetState();
}

class _SearchSelectionSheetState extends State<SearchSelectionSheet> {
  late List<String> _filteredOptions;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredOptions = widget.options;
  }

  void _filter(String query) {
    setState(() {
      _filteredOptions = widget.options
          .where((opt) => opt.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      color: CupertinoColors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.title, style: const TextStyle(color: CupertinoColors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Fechar'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Buscar...',
                style: const TextStyle(color: CupertinoColors.white),
                onChanged: _filter,
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 16),
                itemCount: _filteredOptions.length,
                itemBuilder: (context, index) {
                  final option = _filteredOptions[index];
                  return _OptionTile(
                    title: Text(option, style: const TextStyle(color: CupertinoColors.white)),
                    onTap: () {
                      widget.onSelected(option);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final Widget title;
  final VoidCallback onTap;

  const _OptionTile({super.key, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CupertinoColors.darkBackgroundGray)),
        ),
        child: title,
      ),
    );
  }
}

String _formatCnpj(String cnpj) {
  final d = cnpj.replaceAll(RegExp(r'\D'), '');
  if (d.length != 14) return cnpj;
  return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12, 14)}';
}

String _formatFaturamento(String? raw) {
  if (raw == null || raw.isEmpty) return 'N/A';
  return raw.replaceAllMapped(
    RegExp(r'(\d+),(\d{2})'),
    (m) {
      final intPart = m[1]!;
      final buf = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
        buf.write(intPart[i]);
      }
      return '$buf,${m[2]!}';
    },
  );
}

class CompanyDetailsModal extends ConsumerWidget {
  final Company company;
  const CompanyDetailsModal({super.key, required this.company});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(hubspotNotesProvider(company.cnpj ?? ''));
    final contactsAsync = ref.watch(hubspotContactsProvider(company.cnpj ?? ''));

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey4,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                GestureDetector(
                  onTap: () => _copyToClipboard(context, company.fantasyName ?? company.name ?? 'Empresa'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(company.fantasyName ?? company.name ?? 'Empresa',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: CupertinoColors.black)),
                      ),
                      const Icon(CupertinoIcons.doc_on_doc, size: 18, color: CupertinoColors.systemGrey),
                    ],
                  ),
                ),
                if (company.fantasyName != null && company.name != null)
                  Text(company.name!,
                    style: const TextStyle(fontSize: 14, color: CupertinoColors.systemGrey)),
                if (company.cnpj != null && company.cnpj!.isNotEmpty)
                  Text(
                    _formatCnpj(company.cnpj!),
                    style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey, letterSpacing: 0.3),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${company.distance?.toStringAsFixed(2)} km de você',
                      style: const TextStyle(
                          fontSize: 16,
                          color: CupertinoColors.activeBlue,
                          fontWeight: FontWeight.w600),
                    ),
                    if (company.latitude != null && company.longitude != null)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: CupertinoColors.activeBlue,
                        borderRadius: BorderRadius.circular(20),
                        minSize: 0,
                        onPressed: () => _openRoute(company.latitude!, company.longitude!),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.location_fill,
                                size: 14, color: CupertinoColors.white),
                            SizedBox(width: 4),
                            Text('Traçar Rota',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: CupertinoColors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildHighlights(),
                const SizedBox(height: 16),
                _buildActionButtons(context),
                const SizedBox(height: 20),
                _buildSection(context, 'Contatos e Endereço', [
                  _tile(context, 'Telefone', company.telefone, CupertinoIcons.phone),
                  _tile(context, 'Email', company.email, CupertinoIcons.mail),
                  _tile(context, 'Endereço', company.address, CupertinoIcons.location),
                ]),
                _buildCrmContacts(contactsAsync),
                if (company.isClient != true)
                  _buildSection(context, 'Dados de Crédito e Dívida', [
                    _tile(context, 'Saúde Tributária', company.saudeTributaria, CupertinoIcons.chart_bar),
                    _tile(context, 'Dívida Ativa', company.dividaAtiva, CupertinoIcons.exclamationmark_shield),
                    _tile(context, 'Score', company.scorePropensao, CupertinoIcons.star_circle),
                  ]),
                _buildSection(context, 'Informações', [
                  _tile(context, 'CNAE', company.cnaePrincipal, CupertinoIcons.doc_text),
                  _tile(context, 'Natureza Jurídica', company.naturezaJuridica, CupertinoIcons.briefcase),
                ]),
                _buildActivities(context, notesAsync),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRoute(double lat, double lng) async {
    // Tenta Google Maps primeiro, depois Apple Maps, depois browser
    final googleMaps = Uri.parse(
        'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
    final appleMaps = Uri.parse('maps://?daddr=$lat,$lng&dirflg=d');
    final webMaps = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');

    if (await canLaunchUrl(googleMaps)) {
      await launchUrl(googleMaps);
    } else if (await canLaunchUrl(appleMaps)) {
      await launchUrl(appleMaps);
    } else {
      await launchUrl(webMaps, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildActivities(BuildContext context, AsyncValue<List<HubSpotNote>> notesAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(CupertinoIcons.chat_bubble_text, size: 16, color: CupertinoColors.systemGrey),
              SizedBox(width: 6),
              Text('Histórico de Atividades',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: CupertinoColors.systemGrey)),
            ],
          ),
        ),
        notesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (e, _) => _noteError('Não foi possível carregar o histórico do CRM.'),
          data: (notes) {
            if (company.cnpj == null || company.cnpj!.isEmpty) {
              return _noteEmpty('CNPJ não disponível para busca no CRM.');
            }
            if (notes.isEmpty) {
              return _noteEmpty('Nenhuma atividade registrada no CRM para esta empresa.');
            }
            return Column(
              children: notes.map((note) => _noteCard(note)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _noteCard(HubSpotNote note) {
    final dateStr = _formatDate(note.timestamp);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.person_circle, size: 14, color: CupertinoColors.activeBlue),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  note.ownerName ?? 'Usuário desconhecido',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: CupertinoColors.activeBlue),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                dateStr,
                style: const TextStyle(fontSize: 11, color: CupertinoColors.systemGrey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            note.body,
            style: const TextStyle(fontSize: 13, color: CupertinoColors.black),
          ),
        ],
      ),
    );
  }

  Widget _noteEmpty(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg,
            style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
            textAlign: TextAlign.center),
      );

  Widget _noteError(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg,
            style: const TextStyle(fontSize: 13, color: CupertinoColors.systemRed)),
      );

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';


  void _copyToClipboard(BuildContext context, String text) {
    if (text.isNotEmpty && text != 'Não informado') {
      Clipboard.setData(ClipboardData(text: text));
      // Feedback visual simples usando Cupertino
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Copiado'),
          content: Text('"$text" copiado para a área de transferência.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      // Opcional: fechar automaticamente após 1 segundo
      Future.delayed(const Duration(seconds: 1), () {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
    }
  }

  Widget _buildCrmContacts(AsyncValue<List<HubSpotContact>> contactsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(CupertinoIcons.person_2, size: 16, color: CupertinoColors.systemGrey),
              SizedBox(width: 6),
              Text(
                'Contatos CRM',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: CupertinoColors.systemGrey),
              ),
            ],
          ),
        ),
        contactsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Não foi possível carregar os contatos do CRM.',
              style: TextStyle(fontSize: 13, color: CupertinoColors.systemRed),
            ),
          ),
          data: (contacts) {
            if (contacts.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nenhum contato registrado no CRM.',
                  style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                ),
              );
            }
            return Column(children: contacts.map(_contactCard).toList());
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _contactCard(HubSpotContact contact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.person_circle_fill, size: 36, color: CupertinoColors.activeBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.nome,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: CupertinoColors.black),
                ),
                if (contact.telefone != null && contact.telefone!.isNotEmpty)
                  Text(contact.telefone!, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
                if (contact.email != null && contact.email!.isNotEmpty)
                  Text(contact.email!, style: const TextStyle(fontSize: 12, color: CupertinoColors.systemGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: CupertinoIcons.person_add,
            label: 'Novo Contato',
            onTap: () => showCupertinoModalPopup(
              context: context,
              builder: (_) => _AddContactSheet(company: company),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: CupertinoIcons.text_bubble,
            label: 'Nova Nota',
            onTap: () => showCupertinoModalPopup(
              context: context,
              builder: (_) => _AddNoteSheet(company: company),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHighlights() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _hItem('Segmento', company.segment, CupertinoIcons.tag),
        _hItem('Fat. Estimado', _formatFaturamento(company.faturamento), CupertinoIcons.money_dollar),
        _hItem('Funcionários', company.funcionarios?.split(' ').first, CupertinoIcons.person_2),
      ],
    );
  }

  Widget _hItem(String l, String? v, IconData i) {
    return Expanded(child: Column(children: [
      Icon(i, color: CupertinoColors.activeBlue, size: 20),
      Text(l, style: const TextStyle(fontSize: 10, color: CupertinoColors.systemGrey)),
      Text(v ?? 'N/A', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: CupertinoColors.black), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
    ]));
  }

  Widget _buildSection(BuildContext context, String t, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: CupertinoColors.systemGrey))),
      ...children,
      const SizedBox(height: 10),
    ]);
  }

  Widget _tile(BuildContext context, String l, String? v, IconData i) {
    final bool hasValue = v != null && v != 'Não informado';
    return GestureDetector(
      onTap: hasValue ? () => _copyToClipboard(context, v) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: CupertinoColors.systemGroupedBackground, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(i, size: 18, color: CupertinoColors.activeBlue),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: const TextStyle(fontSize: 10, color: CupertinoColors.systemGrey)),
            Text(v ?? 'Não informado', style: const TextStyle(fontSize: 14, color: CupertinoColors.black)),
          ])),
          if (hasValue)
            const Icon(CupertinoIcons.doc_on_doc, size: 16, color: CupertinoColors.systemGrey),
        ]),
      ),
    );
  }
}

// ─── Botão de ação ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.activeBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CupertinoColors.activeBlue.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: CupertinoColors.activeBlue),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.activeBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet: Nova Nota ─────────────────────────────────────────────────────────

class _AddNoteSheet extends ConsumerStatefulWidget {
  final Company company;
  const _AddNoteSheet({required this.company});

  @override
  ConsumerState<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends ConsumerState<_AddNoteSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() { _loading = true; _error = null; });
    final nav = Navigator.of(context);

    try {
      await ref.read(hubspotServiceProvider).addNoteToCompany(
            cnpj: widget.company.cnpj ?? '',
            noteText: text,
          );
      ref.invalidate(hubspotNotesProvider(widget.company.cnpj ?? ''));
      if (mounted) setState(() { _success = true; _loading = false; });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nova Nota',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: CupertinoColors.black),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _controller,
                placeholder: 'Digite a observação...',
                maxLines: 5,
                minLines: 4,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGroupedBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: CupertinoColors.systemRed, fontSize: 13)),
              ],
              if (_success) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.checkmark_circle_fill, color: CupertinoColors.systemGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Nota salva com sucesso!',
                          style: TextStyle(color: CupertinoColors.systemGreen, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              if (!_success) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.systemGrey5,
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed: _loading ? null : () => Navigator.pop(context),
                        child: const Text('Cancelar', style: TextStyle(color: CupertinoColors.black)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.activeBlue,
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed: _loading ? null : _save,
                        child: _loading
                            ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                            : const Text(
                                'Salvar',
                                style: TextStyle(color: CupertinoColors.white, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sheet: Novo Contato ──────────────────────────────────────────────────────

class _AddContactSheet extends ConsumerStatefulWidget {
  final Company company;
  const _AddContactSheet({required this.company});

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nome = _nomeController.text.trim();
    final telefone = _telefoneController.text.trim();
    final email = _emailController.text.trim();

    if (nome.isEmpty || telefone.isEmpty) {
      setState(() => _error = 'Nome e telefone são obrigatórios.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final nav = Navigator.of(context);

    try {
      await ref.read(hubspotServiceProvider).addContactToCompany(
            cnpj: widget.company.cnpj ?? '',
            nome: nome,
            telefone: telefone,
            email: email.isEmpty ? null : email,
          );
      ref.invalidate(hubspotContactsProvider(widget.company.cnpj ?? ''));
      if (mounted) setState(() { _success = true; _loading = false; });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String placeholder, {
    TextInputType? keyboardType,
  }) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Novo Contato',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: CupertinoColors.black),
              ),
              const SizedBox(height: 12),
              _field(_nomeController, 'Nome *'),
              const SizedBox(height: 8),
              _field(_telefoneController, 'Telefone *', keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              _field(_emailController, 'E-mail (opcional)', keyboardType: TextInputType.emailAddress),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: CupertinoColors.systemRed, fontSize: 13)),
              ],
              if (_success) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.checkmark_circle_fill, color: CupertinoColors.systemGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Contato salvo com sucesso!',
                          style: TextStyle(color: CupertinoColors.systemGreen, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              if (!_success) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.systemGrey5,
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed: _loading ? null : () => Navigator.pop(context),
                        child: const Text('Cancelar', style: TextStyle(color: CupertinoColors.black)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.activeBlue,
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed: _loading ? null : _save,
                        child: _loading
                            ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                            : const Text(
                                'Salvar',
                                style: TextStyle(color: CupertinoColors.white, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
