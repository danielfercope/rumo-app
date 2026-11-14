import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../groups/providers/group_provider.dart';
import '../data/company_repository.dart';

/// Raio da busca no mapa: de 1 a 100 km (mais que isso deixa de ser "perto"),
/// com atalhos pros valores mais usados.
const double minRadiusKm = 1;
const double maxRadiusKm = 100;
const List<double> radiusPresetsKm = [5, 10, 30, 100];

class MapFilters {
  final String? segment;
  final String? product;
  final String? type;
  final String? state;
  final String? city;
  final String? cnae;
  final double radius;

  MapFilters({
    this.segment,
    this.product,
    this.type,
    this.state,
    this.city,
    this.cnae,
    this.radius = 5.0,
  });

  MapFilters copyWith({
    String? segment,
    bool clearSegment = false,
    String? product,
    bool clearProduct = false,
    String? type,
    bool clearType = false,
    String? state,
    bool clearState = false,
    String? city,
    bool clearCity = false,
    String? cnae,
    bool clearCnae = false,
    double? radius,
  }) {
    final effectiveState = clearState ? null : (state ?? this.state);
    final stateChanged = effectiveState != this.state;

    return MapFilters(
      segment: clearSegment ? null : (segment ?? this.segment),
      product: clearProduct ? null : (product ?? this.product),
      type: clearType ? null : (type ?? this.type),
      state: effectiveState,
      // Uma cidade só faz sentido dentro do estado a que pertence: se o
      // estado mudou e nenhuma cidade nova foi informada, a cidade antiga
      // é descartada em vez de ficar "presa" a um estado diferente.
      city: clearCity ? null : (city ?? (stateChanged ? null : this.city)),
      cnae: clearCnae ? null : (cnae ?? this.cnae),
      radius: (radius ?? this.radius).clamp(minRadiusKm, maxRadiusKm),
    );
  }

  bool get isEmpty =>
      segment == null &&
      product == null &&
      type == null &&
      state == null &&
      city == null &&
      cnae == null &&
      radius == 5.0;
}

class MapFiltersNotifier extends Notifier<MapFilters> {
  @override
  MapFilters build() => MapFilters();

  void setSegment(String? v) =>
      state = state.copyWith(segment: v, clearSegment: v == null);

  void setProduct(String? v) =>
      state = state.copyWith(product: v, clearProduct: v == null);

  void setType(String? v) =>
      state = state.copyWith(type: v, clearType: v == null);

  void setUf(String? v) =>
      state = state.copyWith(state: v, clearState: v == null);

  void setCity(String? v) =>
      state = state.copyWith(city: v, clearCity: v == null);

  void setCnae(String? v) =>
      state = state.copyWith(cnae: v, clearCnae: v == null);

  void setRadius(double v) => state = state.copyWith(radius: v);

  void apply(MapFilters filters) => state = filters;

  void clear() => state = MapFilters();
}

final mapFiltersProvider =
    NotifierProvider<MapFiltersNotifier, MapFilters>(MapFiltersNotifier.new);

final filterOptionsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repository = ref.watch(companyRepositoryProvider);
  // Sem organização não há opções (e o servidor devolveria vazio de qualquer jeito).
  final groupId = ref.watch(activeGroupProvider)?.group.id;
  if (groupId == null) {
    return {
      'segments': <String>[],
      'products': <String>[],
      'states': <String>[],
      'cnaes': <String>[],
      'stateToCities': <String, List<String>>{},
    };
  }
  return await repository.getFilterOptions();
});

final filteredCitiesProvider = Provider<List<String>>((ref) {
  final allOptions = ref.watch(filterOptionsProvider).value;
  final filters = ref.watch(mapFiltersProvider);

  if (allOptions == null) return [];

  if (filters.state != null) {
    final stateToCities = allOptions['stateToCities'] as Map<String, dynamic>?;
    final cities = stateToCities?[filters.state] as List<dynamic>?;
    return cities?.cast<String>() ?? [];
  }

  return (allOptions['cities'] as List? ?? []).cast<String>();
});
