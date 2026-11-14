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
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(middle: Text('Organização')),
      child: SafeArea(
        child: groupsAsync.when(
          data: (groups) => groups.isEmpty
              ? const GroupOnboardingView()
              : const GroupManagementView(),
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Não foi possível carregar sua organização',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('$e',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: CupertinoColors.systemGrey)),
                  const SizedBox(height: 12),
                  CupertinoButton.filled(
                    onPressed: () => ref.invalidate(myGroupsProvider),
                    child: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
