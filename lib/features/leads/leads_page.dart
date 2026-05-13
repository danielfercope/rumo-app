import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../map/providers/filter_provider.dart';
import '../map/models/company_model.dart';
import '../map/presentation/filter_modal.dart';
import '../map/presentation/company_details_modal.dart';
import 'leads_search_provider.dart';

bool _looksLikeCnpj(String query) {
  if (query.isEmpty) return false;
  final digitCount = query.replaceAll(RegExp(r'[^\d]'), '').length;
  return RegExp(r'^[\d.\-/\s]+$').hasMatch(query) && digitCount >= 3;
}

class LeadsPage extends ConsumerStatefulWidget {
  const LeadsPage({super.key});

  @override
  ConsumerState<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends ConsumerState<LeadsPage> {
  int _selectedSegment = 0;
  String _searchQuery = '';
  bool _isCnpjMode = false;
  Timer? _debounce;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final isCnpj = _looksLikeCnpj(value);
    setState(() {
      _searchQuery = value;
      _isCnpjMode = isCnpj;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(leadsSearchQueryProvider.notifier).state = LeadsSearchQuery(
        query: value,
        isCnpj: isCnpj,
      );
    });
  }

  List<Company> _applySegment(List<Company> all) {
    switch (_selectedSegment) {
      case 1:
        return all.where((c) => c.isClient != true).toList();
      case 2:
        return all.where((c) => c.isClient == true).toList();
      default:
        return all;
    }
  }

  int _activeFilterCount(MapFilters filters) {
    int count = 0;
    if (filters.segment != null) count++;
    if (filters.product != null) count++;
    if (filters.type != null) count++;
    if (filters.state != null) count++;
    if (filters.city != null) count++;
    if (filters.cnae != null) count++;
    if (filters.radius != 5.0) count++;
    return count;
  }

  void _openFilters() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => const FilterModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(leadsResultsProvider);
    final filters = ref.watch(mapFiltersProvider);
    final filterCount = _activeFilterCount(filters);

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Meus Leads'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      onPressed: _openFilters,
                      child: const Icon(CupertinoIcons.slider_horizontal_3),
                    ),
                    if (filterCount > 0)
                      Positioned(
                        right: 4,
                        top: 6,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: CupertinoColors.activeBlue,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$filterCount',
                              style: const TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Icon(CupertinoIcons.add),
                  onPressed: null,
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CupertinoSearchTextField(
                    controller: _searchController,
                    placeholder: 'Nome da empresa ou CNPJ...',
                    onChanged: _onSearchChanged,
                    onSuffixTap: () {
                      _debounce?.cancel();
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _isCnpjMode = false;
                      });
                      ref.read(leadsSearchQueryProvider.notifier).state =
                          const LeadsSearchQuery();
                    },
                  ),
                  if (_searchQuery.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _SearchModeChip(isCnpjMode: _isCnpjMode),
                  ],
                  if (filterCount > 0) ...[
                    const SizedBox(height: 10),
                    _ActiveFiltersRow(filters: filters),
                  ],
                  const SizedBox(height: 16),
                  CupertinoSlidingSegmentedControl<int>(
                    groupValue: _selectedSegment,
                    children: const {
                      0: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Todos')),
                      1: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Ativos')),
                      2: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Ganhos')),
                    },
                    onValueChanged: (v) => setState(() => _selectedSegment = v ?? 0),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          resultsAsync.when(
            data: (companies) {
              if (companies == null) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Digite um nome ou CNPJ — ou aplique filtros — para consultar leads.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: CupertinoColors.systemGrey),
                      ),
                    ),
                  ),
                );
              }

              final filtered = _applySegment(companies);

              if (filtered.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Nenhuma empresa encontrada.',
                      style: TextStyle(color: CupertinoColors.systemGrey),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final company = filtered[index];
                    return CupertinoListTile(
                      title: Text(company.fantasyName ?? company.name ?? 'Empresa'),
                      subtitle: Text(company.segment ?? 'Sem segmento'),
                      trailing: const CupertinoListTileChevron(),
                      onTap: () {
                        showCupertinoModalPopup(
                          context: context,
                          builder: (context) => CompanyDetailsModal(company: company),
                        );
                      },
                    );
                  },
                  childCount: filtered.length,
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            ),
            error: (e, s) => const SliverFillRemaining(
              child: Center(child: Text('Erro ao carregar empresas')),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchModeChip extends StatelessWidget {
  final bool isCnpjMode;

  const _SearchModeChip({required this.isCnpjMode});

  @override
  Widget build(BuildContext context) {
    final color = isCnpjMode ? CupertinoColors.activeOrange : CupertinoColors.activeBlue;
    final icon = isCnpjMode ? CupertinoIcons.number : CupertinoIcons.building_2_fill;
    final label = isCnpjMode ? 'Buscando por CNPJ' : 'Buscando por nome';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha:0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _ActiveFiltersRow extends ConsumerWidget {
  final MapFilters filters;

  const _ActiveFiltersRow({required this.filters});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(mapFiltersProvider.notifier);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (filters.segment != null)
            _FilterChip(
              label: filters.segment!,
              onRemove: () => notifier.setSegment(null),
            ),
          if (filters.product != null)
            _FilterChip(
              label: filters.product!,
              onRemove: () => notifier.setProduct(null),
            ),
          if (filters.type != null)
            _FilterChip(
              label: filters.type == 'client' ? 'Cliente' : 'Lead',
              onRemove: () => notifier.setType(null),
            ),
          if (filters.state != null)
            _FilterChip(
              label: filters.state!,
              onRemove: () => notifier.setUf(null),
            ),
          if (filters.city != null)
            _FilterChip(
              label: filters.city!,
              onRemove: () => notifier.setCity(null),
            ),
          if (filters.cnae != null)
            _FilterChip(
              label: 'CNAE: ${filters.cnae!.length > 12 ? '${filters.cnae!.substring(0, 12)}…' : filters.cnae!}',
              onRemove: () => notifier.setCnae(null),
            ),
          if (filters.radius != 5.0)
            _FilterChip(
              label: '${filters.radius.toInt()} km',
              onRemove: () => notifier.setRadius(5.0),
            ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => notifier.clear(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: CupertinoColors.systemRed.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: CupertinoColors.systemRed.withValues(alpha:0.3)),
              ),
              child: const Text(
                'Limpar tudo',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _FilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: CupertinoColors.activeBlue.withValues(alpha:0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: CupertinoColors.activeBlue.withValues(alpha:0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.activeBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(CupertinoIcons.xmark, size: 12, color: CupertinoColors.activeBlue),
            ),
          ],
        ),
      ),
    );
  }
}
