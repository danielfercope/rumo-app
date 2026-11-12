import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_model.dart';
import '../providers/group_provider.dart';

/// Estado vazio da aba "Equipe": o usuário ainda não pertence a nenhum
/// grupo. Não bloqueia o resto do app (Radar/Leads funcionam normalmente
/// sem grupo) — é só o conteúdo desta aba enquanto `myGroupsProvider`
/// estiver vazio.
class GroupOnboardingView extends ConsumerStatefulWidget {
  const GroupOnboardingView(
      {super.key, this.onCreated, this.showHeader = true});

  /// Chamado com a organização criada (antes de recarregar a lista).
  final void Function(Group group)? onCreated;

  /// Mostra o título "Você ainda não faz parte de nenhuma organização".
  final bool showHeader;

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
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.showHeader) ...[
          const SizedBox(height: 12),
          const Text(
            'Você ainda não faz parte de nenhuma organização',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
        ],
        const Text('Criar uma nova organização',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: _nameController,
          placeholder: 'Nome da organização',
          enabled: !_loading,
        ),
        const SizedBox(height: 8),
        CupertinoButton.filled(
          onPressed: _loading ? null : _createGroup,
          child: const Text('Criar organização'),
        ),
        const SizedBox(height: 32),
        const Text('Entrar com um convite',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        CupertinoTextField(
          controller: _hashController,
          placeholder: 'Cole aqui o código de convite',
          enabled: !_loading,
        ),
        const SizedBox(height: 8),
        CupertinoButton.filled(
          onPressed: _loading ? null : _joinGroup,
          child: const Text('Entrar na organização'),
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
