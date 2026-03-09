import 'package:flutter/cupertino.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'providers/location_provider.dart';
import 'providers/company_provider.dart';
import 'providers/filter_provider.dart';
import 'models/company_model.dart';

class RadarPage extends ConsumerStatefulWidget {
  const RadarPage({super.key});

  @override
  ConsumerState<RadarPage> createState() => _RadarPageState();
}

class _RadarPageState extends ConsumerState<RadarPage> {
  late GoogleMapController mapController;
  MapType _currentMapType = MapType.normal;
  bool _showBottomList = true; 
  
  DateTime? _lastTapTime;
  String? _lastTappedMarkerId;

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

  @override
  Widget build(BuildContext context) {
    final locationAsync = ref.watch(locationProvider);
    final companiesAsync = ref.watch(companiesProvider);
    final filters = ref.watch(mapFiltersProvider);

    return CupertinoPageScaffold(
      child: locationAsync.when(
        data: (position) => companiesAsync.when(
          data: (companies) => _buildContent(position, companies, filters.radius),
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (error, stack) => _buildContent(position, [], filters.radius),
        ),
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (error, stack) => companiesAsync.when(
          data: (companies) => _buildContent(null, companies, filters.radius),
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (error, stack) => _buildContent(null, [], filters.radius),
        ),
      ),
    );
  }

  Widget _buildContent(Position? position, List<Company> companies, double radius) {
    final initialTarget = position != null
        ? LatLng(position.latitude, position.longitude)
        : _defaultCenter;

    final List<Company> sorted = List.from(companies)
      ..sort((a, b) => (a.distance ?? 999999).compareTo(b.distance ?? 999999));
    final displayCompanies = sorted.take(3).toList();

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: CameraPosition(target: initialTarget, zoom: 14.0),
          mapType: _currentMapType,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: companies.map((company) {
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
            ],
          ),
        ),

        Positioned(
          bottom: (_showBottomList && displayCompanies.isNotEmpty) ? 200 : 30,
          right: 16,
          child: CupertinoButton(
            padding: const EdgeInsets.all(12),
            color: CupertinoColors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(30),
            onPressed: _centerOnUser,
            child: const Icon(CupertinoIcons.location_fill, color: CupertinoColors.activeBlue),
          ),
        ),

        if (_showBottomList && displayCompanies.isNotEmpty)
          Positioned(
            bottom: 110,
            left: 16,
            right: 16,
            child: Row(
              children: displayCompanies.map((company) {
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _showCompanyDetails(company),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CupertinoColors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: CupertinoColors.black.withOpacity(0.1), blurRadius: 4)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(company.fantasyName ?? company.name ?? 'Empresa', 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: CupertinoColors.black), 
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (company.fantasyName != null && company.name != null)
                            Text(company.name!, 
                              style: const TextStyle(fontSize: 8, color: CupertinoColors.systemGrey), 
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(company.segment ?? 'N/A', 
                            style: const TextStyle(fontSize: 9, color: CupertinoColors.activeBlue, fontWeight: FontWeight.w500), 
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${company.distance?.toStringAsFixed(1)}km', 
                            style: const TextStyle(fontSize: 10, color: CupertinoColors.black, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
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
            const Text('Alcance da Busca', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: CupertinoColors.white)),
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
                  return CupertinoListTile(
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

class CupertinoListTile extends StatelessWidget {
  final Widget title;
  final VoidCallback onTap;

  const CupertinoListTile({super.key, required this.title, required this.onTap});

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

class CompanyDetailsModal extends StatelessWidget {
  final Company company;
  const CompanyDetailsModal({super.key, required this.company});

  @override
  Widget build(BuildContext context) {
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
                Text(company.fantasyName ?? company.name ?? 'Empresa', 
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: CupertinoColors.black)),
                if (company.fantasyName != null && company.name != null)
                  Text(company.name!, 
                    style: const TextStyle(fontSize: 14, color: CupertinoColors.systemGrey)),
                Text('${company.distance?.toStringAsFixed(2)} km de você', 
                  style: const TextStyle(fontSize: 16, color: CupertinoColors.activeBlue, fontWeight: FontWeight.w600)),
                const SizedBox(height: 20),
                _buildHighlights(),
                const SizedBox(height: 20),
                _buildSection('Contatos e Endereço', [
                  _tile('Telefone', company.telefone, CupertinoIcons.phone),
                  _tile('Email', company.email, CupertinoIcons.mail),
                  _tile('Endereço', company.address, CupertinoIcons.location),
                ]),
                _buildSection('Dados de Crédito e Dívida', [
                  _tile('Saúde Tributária', company.saudeTributaria, CupertinoIcons.chart_bar),
                  _tile('Dívida Ativa', company.dividaAtiva, CupertinoIcons.exclamationmark_shield),
                  _tile('Score', company.scorePropensao, CupertinoIcons.star_circle),
                ]),
                _buildSection('Atividades', [
                  _tile('CNAE', company.cnaePrincipal, CupertinoIcons.doc_text),
                  _tile('Natureza Jurídica', company.naturezaJuridica, CupertinoIcons.briefcase),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlights() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _hItem('Segmento', company.segment, CupertinoIcons.tag),
        _hItem('Faturamento', company.faturamento?.split(' ').last, CupertinoIcons.money_dollar),
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

  Widget _buildSection(String t, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(t, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: CupertinoColors.systemGrey))),
      ...children,
      const SizedBox(height: 10),
    ]);
  }

  Widget _tile(String l, String? v, IconData i) {
    return Container(
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
      ]),
    );
  }
}
