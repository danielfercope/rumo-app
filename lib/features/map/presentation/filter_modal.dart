import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/filter_provider.dart';

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
              const Text('Filtros Avançados',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: CupertinoColors.white)),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () {
                  ref.read(mapFiltersProvider.notifier).apply(_tempFilters);
                  Navigator.pop(context);
                },
                child: const Text('Aplicar',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: optionsAsync.when(
              data: (options) {
                final List<String> citiesForState;
                if (_tempFilters.state != null) {
                  final stateToCities =
                      options['stateToCities'] as Map<String, dynamic>?;
                  final cities =
                      stateToCities?[_tempFilters.state] as List<dynamic>?;
                  citiesForState = cities?.cast<String>() ?? [];
                } else {
                  citiesForState =
                      (options['cities'] as List? ?? []).cast<String>();
                }

                return ListView(
                  children: [
                    _buildRadiusSection(),
                    const SizedBox(height: 24),
                    _buildSearchableField(
                        'Segmento',
                        _tempFilters.segment,
                        (options['segments'] as List? ?? []).cast<String>(),
                        (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(
                          segment: v, clearSegment: v == null));
                    }),
                    _buildSearchableField(
                        'Produto',
                        _tempFilters.product,
                        (options['products'] as List? ?? []).cast<String>(),
                        (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(
                          product: v, clearProduct: v == null));
                    }),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Tipo de Empresa',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.systemGrey)),
                    ),
                    CupertinoSlidingSegmentedControl<String>(
                      backgroundColor: CupertinoColors.darkBackgroundGray,
                      thumbColor: CupertinoColors.activeBlue,
                      groupValue: _tempFilters.type ?? 'all',
                      children: {
                        'all': _segmentedText(
                            'Todos', _tempFilters.type == null),
                        'client': _segmentedText(
                            'Cliente', _tempFilters.type == 'client'),
                        'lead': _segmentedText(
                            'Lead', _tempFilters.type == 'lead'),
                      },
                      onValueChanged: (v) {
                        setState(() => _tempFilters = _tempFilters.copyWith(
                            type: v == 'all' ? null : v,
                            clearType: v == 'all'));
                      },
                    ),
                    _buildSearchableField(
                        'Estado (UF)',
                        _tempFilters.state,
                        (options['states'] as List? ?? []).cast<String>(),
                        (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(
                          state: v, clearState: v == null));
                    }),
                    _buildSearchableField(
                        'Cidade', _tempFilters.city, citiesForState, (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(
                          city: v, clearCity: v == null));
                    }),
                    _buildSearchableField(
                        'CNAE',
                        _tempFilters.cnae,
                        (options['cnaes'] as List? ?? []).cast<String>(),
                        (v) {
                      setState(() => _tempFilters = _tempFilters.copyWith(
                          cnae: v, clearCnae: v == null));
                    }),
                    const SizedBox(height: 40),
                    CupertinoButton(
                      color: CupertinoColors.systemRed.withOpacity(0.2),
                      onPressed: () {
                        setState(() => _tempFilters = MapFilters());
                      },
                      child: const Text('Limpar Todos',
                          style: TextStyle(
                              color: CupertinoColors.systemRed,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                  child: CupertinoActivityIndicator(
                      color: CupertinoColors.white)),
              error: (e, s) => const Center(
                  child: Text('Erro ao carregar opções',
                      style: TextStyle(color: CupertinoColors.white))),
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
            const Text('Raio de Destaque no Mapa',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.white)),
            Text('${_tempFilters.radius.toInt()} km',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.activeBlue)),
          ],
        ),
        const SizedBox(height: 8),
        CupertinoSlider(
          value: _tempFilters.radius,
          min: 1,
          max: 15000,
          onChanged: (v) =>
              setState(() => _tempFilters = _tempFilters.copyWith(radius: v)),
        ),
      ],
    );
  }

  Widget _segmentedText(String text, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 13,
              color: isSelected
                  ? CupertinoColors.white
                  : CupertinoColors.systemGrey,
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal)),
    );
  }

  Widget _buildSearchableField(String label, String? currentValue,
      List<String> options, Function(String?) onSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(label,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.systemGrey)),
        ),
        GestureDetector(
          onTap: () => _showSearchPicker(label, options, onSelected),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: CupertinoColors.darkBackgroundGray,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: CupertinoColors.systemGrey.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    currentValue ?? 'Selecione...',
                    style: TextStyle(
                      color: currentValue == null
                          ? CupertinoColors.systemGrey2
                          : CupertinoColors.white,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (currentValue != null)
                  GestureDetector(
                    onTap: () => onSelected(null),
                    child: const Icon(CupertinoIcons.clear_circled_solid,
                        size: 20, color: CupertinoColors.systemGrey),
                  )
                else
                  const Icon(CupertinoIcons.chevron_down,
                      size: 16, color: CupertinoColors.systemGrey2),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showSearchPicker(
      String title, List<String> options, Function(String?) onSelected) {
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
                  Text(widget.title,
                      style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
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
                    title: Text(option,
                        style:
                            const TextStyle(color: CupertinoColors.white)),
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
          border: Border(
              bottom: BorderSide(color: CupertinoColors.darkBackgroundGray)),
        ),
        child: title,
      ),
    );
  }
}
