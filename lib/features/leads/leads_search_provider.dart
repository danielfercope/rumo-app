import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../map/models/company_model.dart';
import '../map/providers/company_provider.dart';
import '../map/providers/filter_provider.dart';

class LeadsSearchQuery {
  final String query;
  final bool isCnpj;

  const LeadsSearchQuery({this.query = '', this.isCnpj = false});

  String get normalized => query.trim();
  bool get isEmpty => normalized.isEmpty;
}

final leadsSearchQueryProvider =
    StateProvider<LeadsSearchQuery>((ref) => const LeadsSearchQuery());

bool _hasNonRadiusFilter(MapFilters f) =>
    f.segment != null ||
    f.product != null ||
    f.type != null ||
    f.state != null ||
    f.city != null ||
    f.cnae != null;

final leadsResultsProvider = FutureProvider<List<Company>?>((ref) async {
  final search = ref.watch(leadsSearchQueryProvider);
  final filters = ref.watch(mapFiltersProvider);
  final repo = ref.watch(companyRepositoryProvider);

  final hasQuery = !search.isEmpty;
  final hasFilters = _hasNonRadiusFilter(filters);

  if (!hasQuery && !hasFilters) return null;

  return repo.searchByText(
    query: hasQuery ? search.normalized : '',
    isCnpj: search.isCnpj,
    filters: filters,
  );
});
