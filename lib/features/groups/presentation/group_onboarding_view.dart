import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_model.dart';
import '../providers/group_provider.dart';

/// Conteúdo da aba "Organização" de quem ainda não pertence a nenhuma.
///
/// Sem organização não há mapa, busca nem leads: a carteira de clientes é da
/// organização e só os membros a veem. Esta tela explica isso e oferece as duas
/// saídas — criar uma organização (e conectar o CRM em seguida) ou entrar numa
/// que já existe com o código de convite.
class GroupOnboardingView extends ConsumerStatefulWidget {
  const GroupOnboardingView({super.key, this.onCreated});

  /// Chamado com a organização criada (antes de recarregar a lista).
  final void Function(Group group)? onCreated;

  @override
  ConsumerState<GroupOnboardingView> createState() =>
      _GroupOnboardingViewState();
}

class _GroupOnboardingViewState extends ConsumerState<GroupOnboardingView> {
  final _nameController = TextEditingController();
  final _hashController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _hashController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      await action();
      ref.invalidate(myGroupsProvider);
    } catch (e) {
      setState(() => _errorMessage = 'Não foi possível concluir: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _createGroup() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Digite um nome pra organização');
      return;
    }
    _run(() async {
      final group = await ref.read(groupServiceProvider).createGroup(name);
      ref.read(pendingCrmSetupGroupIdProvider.notifier).state = group.id;
      widget.onCreated?.call(group);
    });
  }

  void _joinGroup() {
    final hash = _hashController.text.trim();
    if (hash.isEmpty) {
      setState(() => _errorMessage = 'Cole o código de convite');
      return;
    }
    _run(() => ref.read(groupServiceProvider).joinByHash(hash));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        const Icon(CupertinoIcons.building_2_fill,
            size: 52, color: CupertinoColors.systemYellow),
        const SizedBox(height: 14),
        const Text(
          'Você ainda não faz parte de nenhuma organização',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Crie a sua ou entre em uma existente pra liberar o Radar e os Leads.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: CupertinoColors.systemGrey),
        ),
        const SizedBox(height: 20),
        CupertinoListSection.insetGrouped(
          margin: EdgeInsets.zero,
          header: const Text('Como funciona'),
          children: const [
            _Fact(
              icon: CupertinoIcons.lock_fill,
              color: CupertinoColors.systemIndigo,
              title: 'Cada organização tem a sua carteira',
              subtitle:
                  'Os clientes e leads de uma organização pertencem só a ela. '
                  'Nenhuma outra os enxerga.',
            ),
            _Fact(
              icon: CupertinoIcons.map_fill,
              color: CupertinoColors.systemGreen,
              title: 'Radar e Leads ficam bloqueados',
              subtitle: 'Eles aparecem aqui embaixo assim que você entrar numa '
                  'organização. Por enquanto, só Perfil e Organização.',
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ActionCard(
          icon: CupertinoIcons.plus_circle_fill,
          color: CupertinoColors.systemBlue,
          title: 'Criar uma organização',
          description:
              'Você vira administrador, convida a equipe e conecta o CRM '
              'pra montar a carteira.',
          field: CupertinoTextField(
            controller: _nameController,
            placeholder: 'Nome da organização',
            enabled: !_loading,
          ),
          buttonLabel: 'Criar organização',
          onPressed: _loading ? null : _createGroup,
        ),
        const SizedBox(height: 16),
        _ActionCard(
          icon: CupertinoIcons.person_badge_plus_fill,
          color: CupertinoColors.systemOrange,
          title: 'Entrar com um convite',
          description:
              'Peça o código ao administrador da organização e cole abaixo.',
          field: CupertinoTextField(
            controller: _hashController,
            placeholder: 'Cole aqui o código de convite',
            enabled: !_loading,
          ),
          buttonLabel: 'Entrar na organização',
          onPressed: _loading ? null : _joinGroup,
        ),
        if (_loading) ...[
          const SizedBox(height: 20),
          const Center(child: CupertinoActivityIndicator()),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CupertinoColors.destructiveRed),
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => CupertinoListTile.notched(
        leading: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: CupertinoColors.white),
        ),
        title: Text(title),
        subtitle: Text(subtitle, maxLines: 3),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.field,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final Widget field;
  final String buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemGroupedBackground
            .resolveFrom(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(description,
              style: const TextStyle(
                  fontSize: 14, color: CupertinoColors.systemGrey)),
          const SizedBox(height: 12),
          field,
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}
