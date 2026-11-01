import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/group_provider.dart';
import 'group_management_view.dart';
import 'group_onboarding_view.dart';

class GroupsHomePage extends ConsumerWidget {
  const GroupsHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Equipe')),
      child: SafeArea(
        child: groupsAsync.when(
          data: (groups) => groups.isEmpty
              ? const GroupOnboardingView()
              : const GroupManagementView(),
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('Erro ao carregar grupos: $e')),
        ),
      ),
    );
  }
}
