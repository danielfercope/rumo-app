import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/company_model.dart';
import '../services/company_service.dart';

final companyServiceProvider = Provider<CompanyService>((ref) {
  return CompanyService(Supabase.instance.client);
});

final companiesProvider = FutureProvider<List<Company>>((ref) async {
  final service = ref.watch(companyServiceProvider);
  return await service.getCompanies();
});
