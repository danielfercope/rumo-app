import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/company_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    return MapFilters(
      segment: clearSegment ? null : (segment ?? this.segment),
      product: clearProduct ? null : (product ?? this.product),
      type: clearType ? null : (type ?? this.type),
      state: clearState ? null : (state ?? this.state),
      city: (clearCity || clearState) ? null : (city ?? this.city),
      cnae: clearCnae ? null : (cnae ?? this.cnae),
      radius: radius ?? this.radius,
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

final mapFiltersProvider = StateProvider<MapFilters>((ref) => MapFilters());

// Corrigido para Map<String, dynamic> pois agora inclui o mapa de cidades por estado
final filterOptionsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = CompanyService(Supabase.instance.client);
  return await service.getFilterOptions();
});

// Provider para cidades filtradas pelo estado selecionado
final filteredCitiesProvider = Provider<List<String>>((ref) {
  final allOptions = ref.watch(filterOptionsProvider).value;
  final filters = ref.watch(mapFiltersProvider);
  
  if (allOptions == null) return [];

  if (filters.state != null) {
    final stateToCities = allOptions['stateToCities'] as Map<String, dynamic>?;
    final cities = stateToCities?[filters.state] as List<dynamic>?;
    return cities?.cast<String>() ?? [];
  }

  // Se não tiver estado, tenta retornar a lista geral de cidades se existir
  return (allOptions['cities'] as List? ?? []).cast<String>();
});
