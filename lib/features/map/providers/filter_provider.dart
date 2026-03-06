import 'package:flutter_riverpod/flutter_riverpod.dart';

class MapFilters {
  final String? segment;
  final String? product;
  final String? type; // 'lead', 'client' or null
  final String? state;
  final String? city;
  final String? cnae;

  MapFilters({
    this.segment,
    this.product,
    this.type,
    this.state,
    this.city,
    this.cnae,
  });

  MapFilters copyWith({
    String? segment,
    String? product,
    String? type,
    String? state,
    String? city,
    String? cnae,
  }) {
    return MapFilters(
      segment: segment ?? this.segment,
      product: product ?? this.product,
      type: type ?? this.type,
      state: state ?? this.state,
      city: city ?? this.city,
      cnae: cnae ?? this.cnae,
    );
  }

  bool get isEmpty =>
      segment == null &&
      product == null &&
      type == null &&
      state == null &&
      city == null &&
      cnae == null;
}

final mapFiltersProvider = StateProvider<MapFilters>((ref) => MapFilters());
