import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/company_model.dart';
import '../data/company_repository.dart';
import 'location_provider.dart';
import 'filter_provider.dart';

export '../data/company_repository.dart' show companyRepositoryProvider;

final companiesProvider = FutureProvider<List<Company>>((ref) async {
  final repo = ref.watch(companyRepositoryProvider);
  final locationAsync = ref.watch(locationProvider);
  final filters = ref.watch(mapFiltersProvider);

  final position = locationAsync.value;
  if (position == null) return [];

  return repo.getCompanies(
    userLat: position.latitude,
    userLong: position.longitude,
    filters: filters,
  );
});
