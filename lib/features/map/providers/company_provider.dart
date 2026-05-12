import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/company_model.dart';
import '../services/company_service.dart';
import 'location_provider.dart';
import 'filter_provider.dart';

final companyServiceProvider = Provider<CompanyService>((ref) {
  return CompanyService(Supabase.instance.client);
});

final companiesProvider = FutureProvider<List<Company>>((ref) async {
  final service = ref.watch(companyServiceProvider);
  final locationAsync = ref.watch(locationProvider);
  final filters = ref.watch(mapFiltersProvider);

  final position = locationAsync.value;
  if (position == null) return []; // ainda loading

  return service.getCompanies(
    userLat: position.latitude,
    userLong: position.longitude,
    filters: filters,
  );
});
