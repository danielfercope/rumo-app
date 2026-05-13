import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/company_model.dart';
import '../../company/hubspot_service.dart';

String formatCnpj(String cnpj) {
  final d = cnpj.replaceAll(RegExp(r'\D'), '');
  if (d.length != 14) return cnpj;
  return '${d.substring(0, 2)}.${d.substring(2, 5)}.${d.substring(5, 8)}/${d.substring(8, 12)}-${d.substring(12, 14)}';
}

String formatFaturamento(String? raw) {
  if (raw == null || raw.isEmpty) return 'N/A';
  return raw.replaceAllMapped(
    RegExp(r'(\d+),(\d{2})'),
    (m) {
      final intPart = m[1]!;
      final buf = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
        buf.write(intPart[i]);
      }
      return '$buf,${m[2]!}';
    },
  );
}

class CompanyDetailsModal extends ConsumerWidget {
  final Company company;
  const CompanyDetailsModal({super.key, required this.company});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(hubspotNotesProvider(company.cnpj ?? ''));
    final contactsAsync =
        ref.watch(hubspotContactsProvider(company.cnpj ?? ''));

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey4,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                GestureDetector(
                  onTap: () => _copyToClipboard(
                      context,
                      company.fantasyName ?? company.name ?? 'Empresa'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                            company.fantasyName ?? company.name ?? 'Empresa',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: CupertinoColors.black)),
                      ),
                      const Icon(CupertinoIcons.doc_on_doc,
                          size: 18, color: CupertinoColors.systemGrey),
                    ],
                  ),
                ),
                if (company.fantasyName != null && company.name != null)
                  Text(company.name!,
                      style: const TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.systemGrey)),
                if (company.cnpj != null && company.cnpj!.isNotEmpty)
                  Text(
                    formatCnpj(company.cnpj!),
                    style: const TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemGrey,
                        letterSpacing: 0.3),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${company.distance?.toStringAsFixed(2)} km de você',
                      style: const TextStyle(
                          fontSize: 16,
                          color: CupertinoColors.activeBlue,
                          fontWeight: FontWeight.w600),
                    ),
                    if (company.latitude != null && company.longitude != null)
                      CupertinoButton(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        color: CupertinoColors.activeBlue,
                        borderRadius: BorderRadius.circular(20),
                        minSize: 0,
                        onPressed: () =>
                            _openRoute(company.latitude!, company.longitude!),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.location_fill,
                                size: 14, color: CupertinoColors.white),
                            SizedBox(width: 4),
                            Text('Traçar Rota',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: CupertinoColors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildHighlights(),
                const SizedBox(height: 16),
                _buildActionButtons(context),
                const SizedBox(height: 20),
                _buildSection(context, 'Contatos e Endereço', [
                  _tile(context, 'Telefone', company.telefone,
                      CupertinoIcons.phone),
                  _tile(context, 'Email', company.email,
                      CupertinoIcons.mail),
                  _tile(context, 'Endereço', company.address,
                      CupertinoIcons.location),
                ]),
                _buildCrmContacts(contactsAsync),
                if (company.isClient != true)
                  _buildSection(context, 'Dados de Crédito e Dívida', [
                    _tile(context, 'Saúde Tributária',
                        company.saudeTributaria, CupertinoIcons.chart_bar),
                    _tile(context, 'Dívida Ativa', company.dividaAtiva,
                        CupertinoIcons.exclamationmark_shield),
                    _tile(context, 'Score', company.scorePropensao,
                        CupertinoIcons.star_circle),
                  ]),
                _buildSection(context, 'Informações', [
                  _tile(context, 'CNAE', company.cnaePrincipal,
                      CupertinoIcons.doc_text),
                  _tile(context, 'Natureza Jurídica',
                      company.naturezaJuridica, CupertinoIcons.briefcase),
                ]),
                _buildActivities(context, notesAsync),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openRoute(double lat, double lng) async {
    final googleMaps = Uri.parse(
        'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
    final appleMaps = Uri.parse('maps://?daddr=$lat,$lng&dirflg=d');
    final webMaps = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');

    if (await canLaunchUrl(googleMaps)) {
      await launchUrl(googleMaps);
    } else if (await canLaunchUrl(appleMaps)) {
      await launchUrl(appleMaps);
    } else {
      await launchUrl(webMaps, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildActivities(
      BuildContext context, AsyncValue<List<HubSpotNote>> notesAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(CupertinoIcons.chat_bubble_text,
                  size: 16, color: CupertinoColors.systemGrey),
              SizedBox(width: 6),
              Text('Histórico de Atividades',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: CupertinoColors.systemGrey)),
            ],
          ),
        ),
        notesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (e, _) =>
              _noteError('Não foi possível carregar o histórico do CRM.'),
          data: (notes) {
            if (company.cnpj == null || company.cnpj!.isEmpty) {
              return _noteEmpty(
                  'CNPJ não disponível para busca no CRM.');
            }
            if (notes.isEmpty) {
              return _noteEmpty(
                  'Nenhuma atividade registrada no CRM para esta empresa.');
            }
            return Column(
              children: notes.map((note) => _noteCard(note)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _noteCard(HubSpotNote note) {
    final dateStr = _formatDate(note.timestamp);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.person_circle,
                  size: 14, color: CupertinoColors.activeBlue),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  note.ownerName ?? 'Usuário desconhecido',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.activeBlue),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(dateStr,
                  style: const TextStyle(
                      fontSize: 11, color: CupertinoColors.systemGrey)),
            ],
          ),
          const SizedBox(height: 6),
          Text(note.body,
              style: const TextStyle(
                  fontSize: 13, color: CupertinoColors.black)),
        ],
      ),
    );
  }

  Widget _noteEmpty(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg,
            style: const TextStyle(
                fontSize: 13, color: CupertinoColors.systemGrey),
            textAlign: TextAlign.center),
      );

  Widget _noteError(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(msg,
            style: const TextStyle(
                fontSize: 13, color: CupertinoColors.systemRed)),
      );

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  void _copyToClipboard(BuildContext context, String text) {
    if (text.isNotEmpty && text != 'Não informado') {
      Clipboard.setData(ClipboardData(text: text));
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('Copiado'),
          content:
              Text('"$text" copiado para a área de transferência.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      Future.delayed(const Duration(seconds: 1), () {
        if (Navigator.canPop(context)) Navigator.pop(context);
      });
    }
  }

  Widget _buildCrmContacts(
      AsyncValue<List<HubSpotContact>> contactsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(CupertinoIcons.person_2,
                  size: 16, color: CupertinoColors.systemGrey),
              SizedBox(width: 6),
              Text(
                'Contatos CRM',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.systemGrey),
              ),
            ],
          ),
        ),
        contactsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CupertinoActivityIndicator()),
          ),
          error: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Não foi possível carregar os contatos do CRM.',
              style: TextStyle(
                  fontSize: 13, color: CupertinoColors.systemRed),
            ),
          ),
          data: (contacts) {
            if (contacts.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nenhum contato registrado no CRM.',
                  style: TextStyle(
                      fontSize: 13, color: CupertinoColors.systemGrey),
                ),
              );
            }
            return Column(
                children: contacts.map(_contactCard).toList());
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _contactCard(HubSpotContact contact) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.person_circle_fill,
              size: 36, color: CupertinoColors.activeBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.nome,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.black)),
                if (contact.telefone != null &&
                    contact.telefone!.isNotEmpty)
                  Text(contact.telefone!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemGrey)),
                if (contact.email != null && contact.email!.isNotEmpty)
                  Text(contact.email!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: CupertinoIcons.person_add,
            label: 'Novo Contato',
            onTap: () => showCupertinoModalPopup(
              context: context,
              builder: (_) => _AddContactSheet(company: company),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: CupertinoIcons.text_bubble,
            label: 'Nova Nota',
            onTap: () => showCupertinoModalPopup(
              context: context,
              builder: (_) => _AddNoteSheet(company: company),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHighlights() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _hItem('Segmento', company.segment, CupertinoIcons.tag),
        _hItem('Fat. Estimado', formatFaturamento(company.faturamento),
            CupertinoIcons.money_dollar),
        _hItem('Funcionários', company.funcionarios?.split(' ').first,
            CupertinoIcons.person_2),
      ],
    );
  }

  Widget _hItem(String l, String? v, IconData i) {
    return Expanded(
        child: Column(children: [
      Icon(i, color: CupertinoColors.activeBlue, size: 20),
      Text(l,
          style: const TextStyle(
              fontSize: 10, color: CupertinoColors.systemGrey)),
      Text(v ?? 'N/A',
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: CupertinoColors.black),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
    ]));
  }

  Widget _buildSection(
      BuildContext context, String t, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(t,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: CupertinoColors.systemGrey))),
      ...children,
      const SizedBox(height: 10),
    ]);
  }

  Widget _tile(BuildContext context, String l, String? v, IconData i) {
    final bool hasValue = v != null && v != 'Não informado';
    return GestureDetector(
      onTap: hasValue ? () => _copyToClipboard(context, v) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: CupertinoColors.systemGroupedBackground,
            borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(i, size: 18, color: CupertinoColors.activeBlue),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(l,
                    style: const TextStyle(
                        fontSize: 10,
                        color: CupertinoColors.systemGrey)),
                Text(v ?? 'Não informado',
                    style: const TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.black)),
              ])),
          if (hasValue)
            const Icon(CupertinoIcons.doc_on_doc,
                size: 16, color: CupertinoColors.systemGrey),
        ]),
      ),
    );
  }
}

// ─── Botão de ação ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: CupertinoColors.activeBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: CupertinoColors.activeBlue.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: CupertinoColors.activeBlue),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.activeBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet: Nova Nota ─────────────────────────────────────────────────────────

class _AddNoteSheet extends ConsumerStatefulWidget {
  final Company company;
  const _AddNoteSheet({required this.company});

  @override
  ConsumerState<_AddNoteSheet> createState() => _AddNoteSheetState();
}

class _AddNoteSheetState extends ConsumerState<_AddNoteSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    final nav = Navigator.of(context);

    try {
      await ref.read(hubspotServiceProvider).addNoteToCompany(
            cnpj: widget.company.cnpj ?? '',
            noteText: text,
          );
      ref.invalidate(hubspotNotesProvider(widget.company.cnpj ?? ''));
      if (mounted) setState(() { _success = true; _loading = false; });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Nova Nota',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.black),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _controller,
                placeholder: 'Digite a observação...',
                maxLines: 5,
                minLines: 4,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGroupedBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: CupertinoColors.systemRed, fontSize: 13)),
              ],
              if (_success) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGreen
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.checkmark_circle_fill,
                          color: CupertinoColors.systemGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Nota salva com sucesso!',
                          style: TextStyle(
                              color: CupertinoColors.systemGreen,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              if (!_success) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.systemGrey5,
                        borderRadius: BorderRadius.circular(12),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        onPressed:
                            _loading ? null : () => Navigator.pop(context),
                        child: const Text('Cancelar',
                            style: TextStyle(
                                color: CupertinoColors.black)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.activeBlue,
                        borderRadius: BorderRadius.circular(12),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        onPressed: _loading ? null : _save,
                        child: _loading
                            ? const CupertinoActivityIndicator(
                                color: CupertinoColors.white)
                            : const Text(
                                'Salvar',
                                style: TextStyle(
                                    color: CupertinoColors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sheet: Novo Contato ──────────────────────────────────────────────────────

class _AddContactSheet extends ConsumerStatefulWidget {
  final Company company;
  const _AddContactSheet({required this.company});

  @override
  ConsumerState<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends ConsumerState<_AddContactSheet> {
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _loading = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nome = _nomeController.text.trim();
    final telefone = _telefoneController.text.trim();
    final email = _emailController.text.trim();

    if (nome.isEmpty || telefone.isEmpty) {
      setState(() => _error = 'Nome e telefone são obrigatórios.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final nav = Navigator.of(context);

    try {
      await ref.read(hubspotServiceProvider).addContactToCompany(
            cnpj: widget.company.cnpj ?? '',
            nome: nome,
            telefone: telefone,
            email: email.isEmpty ? null : email,
          );
      ref.invalidate(hubspotContactsProvider(widget.company.cnpj ?? ''));
      if (mounted) setState(() { _success = true; _loading = false; });
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) nav.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String placeholder, {
    TextInputType? keyboardType,
  }) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey4,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Novo Contato',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.black),
              ),
              const SizedBox(height: 12),
              _field(_nomeController, 'Nome *'),
              const SizedBox(height: 8),
              _field(_telefoneController, 'Telefone *',
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 8),
              _field(_emailController, 'E-mail (opcional)',
                  keyboardType: TextInputType.emailAddress),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        color: CupertinoColors.systemRed, fontSize: 13)),
              ],
              if (_success) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGreen
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.checkmark_circle_fill,
                          color: CupertinoColors.systemGreen, size: 18),
                      SizedBox(width: 8),
                      Text('Contato salvo com sucesso!',
                          style: TextStyle(
                              color: CupertinoColors.systemGreen,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              if (!_success) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.systemGrey5,
                        borderRadius: BorderRadius.circular(12),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        onPressed:
                            _loading ? null : () => Navigator.pop(context),
                        child: const Text('Cancelar',
                            style: TextStyle(
                                color: CupertinoColors.black)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton(
                        color: CupertinoColors.activeBlue,
                        borderRadius: BorderRadius.circular(12),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        onPressed: _loading ? null : _save,
                        child: _loading
                            ? const CupertinoActivityIndicator(
                                color: CupertinoColors.white)
                            : const Text(
                                'Salvar',
                                style: TextStyle(
                                    color: CupertinoColors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
