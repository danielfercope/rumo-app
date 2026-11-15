import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/company_model.dart';
import '../../company/crm_service.dart';
import '../../enrichment/models/enrichment_models.dart';
import '../../enrichment/presentation/enrichment_cards.dart';
import '../../enrichment/presentation/google_profile.dart';
import '../../enrichment/providers/enrichment_provider.dart';
import '../../groups/providers/group_provider.dart';
import 'priority_explanation_section.dart';

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
    final notesAsync = ref.watch(crmNotesProvider(company.cnpj ?? ''));
    final contactsAsync = ref.watch(crmContactsProvider(company.cnpj ?? ''));

    final groupId = ref.watch(activeGroupProvider)?.group.id;
    final cnpj = (company.cnpj ?? '').replaceAll(RegExp(r'\D'), '');
    final canEnrich = groupId != null && cnpj.length == 14;
    EnrichmentResult? source(EnrichmentSource fonte) => canEnrich
        ? ref
            .watch(enrichmentProvider(
                (groupId: groupId, cnpj: cnpj, fonte: fonte)))
            .valueOrNull
        : null;

    // O Google é consultado ao abrir: dá a capa e é a fonte preferida de
    // telefone, endereço, site e horário. Sem ele, ficam os do cadastro e,
    // por último, os da Receita.
    final googleAsync = canEnrich
        ? ref.watch(enrichmentProvider(
            (groupId: groupId, cnpj: cnpj, fonte: EnrichmentSource.google)))
        : null;
    final googleResult = googleAsync?.valueOrNull;
    final google = googleResult?.hasData == true
        ? GooglePlaceData.fromJson(googleResult!.dados!)
        : null;
    final receitaResult = source(EnrichmentSource.receita);
    final receita = receitaResult?.hasData == true
        ? ReceitaData.fromJson(receitaResult!.dados!)
        : null;

    final telefone = _firstFilled([
      google?.telefone,
      company.telefone,
      if (receita != null && receita.telefones.isNotEmpty)
        receita.telefones.first,
    ]);
    final email = _firstFilled([company.email, receita?.email]);
    final endereco =
        _firstFilled([google?.endereco, company.address, receita?.endereco]);
    final site = _firstFilled([google?.site]);
    final hoje = google == null ? null : todayHours(google.horarios);

    final creditTiles = [
      if (_filled(company.saudeTributaria))
        _tile(context, 'Saúde Tributária', company.saudeTributaria,
            CupertinoIcons.chart_bar),
      if (_filled(company.dividaAtiva))
        _tile(context, 'Dívida Ativa', company.dividaAtiva,
            CupertinoIcons.exclamationmark_shield),
      if (_filled(company.scorePropensao))
        _tile(context, 'Score', company.scorePropensao,
            CupertinoIcons.star_circle),
    ];
    // CNAE e natureza jurídica já aparecem (completos) no bloco da Receita.
    final infoTiles = receita != null
        ? const <Widget>[]
        : [
            if (_filled(company.cnaePrincipal))
              _tile(context, 'CNAE', company.cnaePrincipal,
                  CupertinoIcons.doc_text),
            if (_filled(company.naturezaJuridica))
              _tile(context, 'Natureza Jurídica', company.naturezaJuridica,
                  CupertinoIcons.briefcase),
          ];

    final hasRoute = company.latitude != null && company.longitude != null;
    final distance = company.distance == null
        ? null
        : '${company.distance!.toStringAsFixed(2)} km de você';
    final infoRows = [
      if (telefone != null)
        _InfoRow(
          icon: CupertinoIcons.phone_fill,
          label: 'Telefone',
          value: telefone,
          onTap: () => _launch(
              'tel:${telefone.replaceAll(RegExp(r'[^0-9+]'), '')}'),
          onCopy: () => _copyToClipboard(context, telefone),
        ),
      if (endereco != null || distance != null)
        _InfoRow(
          icon: CupertinoIcons.location_solid,
          label: 'Endereço',
          value: endereco ?? 'Endereço não informado',
          detail: distance,
          detailAction: hasRoute
              ? _RouteButton(
                  onTap: () =>
                      _openRoute(company.latitude!, company.longitude!))
              : null,
          onTap: hasRoute
              ? () => _openRoute(company.latitude!, company.longitude!)
              : null,
          onCopy: endereco == null
              ? null
              : () => _copyToClipboard(context, endereco),
        ),
      if (hoje != null)
        _HoursRow(today: hoje, horarios: google!.horarios),
      if (email != null)
        _InfoRow(
          icon: CupertinoIcons.mail_solid,
          label: 'E-mail',
          value: email,
          onTap: () => _launch('mailto:$email'),
          onCopy: () => _copyToClipboard(context, email),
        ),
    ];

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GoogleCover(
            place: google,
            loading: googleAsync?.isLoading ?? false,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTap: () => _copyToClipboard(context, company.displayName),
                  child: Text(company.displayName,
                      style: const TextStyle(
                          fontSize: 24,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: CupertinoColors.black)),
                ),
                if (company.name != null && company.name != company.displayName)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(company.name!,
                        style: const TextStyle(
                            fontSize: 14, color: CupertinoColors.systemGrey)),
                  ),
                if (company.cnpj != null && company.cnpj!.isNotEmpty)
                  Text(
                    formatCnpj(company.cnpj!),
                    style: const TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemGrey,
                        letterSpacing: 0.3),
                  ),
                if (google != null) GoogleRatingLine(google),
                const SizedBox(height: 16),
                _buildActionButtons(context),
                if (site != null) ...[
                  const SizedBox(height: 10),
                  _SiteLink(url: site),
                ],
                if (infoRows.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _InfoGroup(rows: infoRows),
                  if (google != null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                          'Telefone, endereço e horário do Google · confira se é a mesma empresa',
                          style: TextStyle(
                              fontSize: 10,
                              color: CupertinoColors.systemGrey)),
                    ),
                ],
                const SizedBox(height: 16),
                if (_buildHighlights() case final Widget highlights) ...[
                  highlights,
                  const SizedBox(height: 16),
                ],
                PriorityExplanationSection(company: company),
                _buildCrmContacts(contactsAsync),
                _buildActivities(context, notesAsync),
                const SizedBox(height: 8),
                if (canEnrich)
                  CompanyEnrichmentCards(groupId: groupId, cnpj: cnpj),
                if (company.isClient != true && creditTiles.isNotEmpty)
                  _buildSection(
                      context, 'Dados de Crédito e Dívida', creditTiles),
                if (infoTiles.isNotEmpty)
                  _buildSection(context, 'Informações', infoTiles),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openRoute(double lat, double lng) async {
    final googleMaps =
        Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving');
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
      BuildContext context, AsyncValue<List<CrmNote>> notesAsync) {
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
              return _noteEmpty('CNPJ não disponível para busca no CRM.');
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

  Widget _noteCard(CrmNote note) {
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
              style:
                  const TextStyle(fontSize: 13, color: CupertinoColors.black)),
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
          content: Text('"$text" copiado para a área de transferência.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      Future.delayed(const Duration(seconds: 1), () {
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  Widget _buildCrmContacts(AsyncValue<List<CrmContact>> contactsAsync) {
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
              style: TextStyle(fontSize: 13, color: CupertinoColors.systemRed),
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
            return Column(children: contacts.map(_contactCard).toList());
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _contactCard(CrmContact contact) {
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
                if (contact.telefone != null && contact.telefone!.isNotEmpty)
                  Text(contact.telefone!,
                      style: const TextStyle(
                          fontSize: 12, color: CupertinoColors.systemGrey)),
                if (contact.email != null && contact.email!.isNotEmpty)
                  Text(contact.email!,
                      style: const TextStyle(
                          fontSize: 12, color: CupertinoColors.systemGrey)),
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

  /// Segmento, faturamento e funcionários — só os que a empresa tem; sem
  /// nenhum, a faixa inteira some (nulo).
  Widget? _buildHighlights() {
    final items = [
      if (_filled(company.segment))
        _hItem('Segmento', company.segment, CupertinoIcons.tag),
      if (_filled(company.faturamento))
        _hItem('Fat. Estimado', formatFaturamento(company.faturamento),
            CupertinoIcons.money_dollar),
      if (_filled(company.funcionarios))
        _hItem('Funcionários', company.funcionarios!.split(' ').first,
            CupertinoIcons.person_2),
    ];
    if (items.isEmpty) return null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: items,
    );
  }

  Widget _hItem(String l, String? v, IconData i) {
    return Expanded(
        child: Column(children: [
      Icon(i, color: CupertinoColors.activeBlue, size: 20),
      Text(l,
          style:
              const TextStyle(fontSize: 10, color: CupertinoColors.systemGrey)),
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

  Widget _buildSection(BuildContext context, String t, List<Widget> children) {
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
                        fontSize: 10, color: CupertinoColors.systemGrey)),
                Text(v ?? 'Não informado',
                    style: const TextStyle(
                        fontSize: 14, color: CupertinoColors.black)),
              ])),
          if (hasValue)
            const Icon(CupertinoIcons.doc_on_doc,
                size: 16, color: CupertinoColors.systemGrey),
        ]),
      ),
    );
  }
}

bool _filled(String? v) {
  final t = v?.trim();
  return t != null && t.isNotEmpty && t != 'N/A' && t != 'Não informado';
}

String? _firstFilled(List<String?> values) {
  for (final v in values) {
    if (_filled(v)) return v!.trim();
  }
  return null;
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
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: CupertinoColors.activeBlue,
      borderRadius: BorderRadius.circular(12),
      minimumSize: Size.zero,
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: CupertinoColors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: CupertinoColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Linhas de contato (estilo lista do iOS) ─────────────────────────────────

class _InfoGroup extends StatelessWidget {
  const _InfoGroup({required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Container(
                margin: const EdgeInsets.only(left: 48),
                height: 0.5,
                color: CupertinoColors.systemGrey4,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.onTap,
    this.onCopy,
    this.detailAction,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final VoidCallback? onTap;
  final VoidCallback? onCopy;
  /// Ação ao lado do [detail] (ex.: "Traçar Rota" junto da distância).
  final Widget? detailAction;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onCopy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: CupertinoColors.activeBlue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: CupertinoColors.systemGrey)),
                  const SizedBox(height: 1),
                  Text(value,
                      style: const TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          color: CupertinoColors.black)),
                  if (detail != null || detailAction != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        if (detail != null)
                          Expanded(
                            child: Text(detail!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.activeBlue)),
                          )
                        else
                          const Spacer(),
                        if (detailAction != null) detailAction!,
                      ]),
                    ),
                ],
              ),
            ),
            if (onCopy != null)
              CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
                onPressed: onCopy,
                child: const Icon(CupertinoIcons.doc_on_doc,
                    size: 16, color: CupertinoColors.systemGrey),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteButton extends StatelessWidget {
  const _RouteButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: CupertinoColors.activeBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        minimumSize: Size.zero,
        onPressed: onTap,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.location_fill,
                size: 13, color: CupertinoColors.activeBlue),
            SizedBox(width: 4),
            Text('Traçar Rota',
                style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.activeBlue,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

/// Horário de hoje; tocar mostra a semana.
class _HoursRow extends StatefulWidget {
  const _HoursRow({required this.today, required this.horarios});
  final String today;
  final List<String> horarios;

  @override
  State<_HoursRow> createState() => _HoursRowState();
}

class _HoursRowState extends State<_HoursRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(CupertinoIcons.clock_fill,
                size: 18, color: CupertinoColors.activeBlue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Horário',
                      style: TextStyle(
                          fontSize: 11, color: CupertinoColors.systemGrey)),
                  const SizedBox(height: 1),
                  Text(widget.today,
                      style: const TextStyle(
                          fontSize: 15, color: CupertinoColors.black)),
                  if (_open)
                    for (final h in widget.horarios)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                            h.isEmpty ? h : h[0].toUpperCase() + h.substring(1),
                            style: const TextStyle(
                                fontSize: 12,
                                color: CupertinoColors.systemGrey)),
                      ),
                ],
              ),
            ),
            Icon(
                _open
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                size: 14,
                color: CupertinoColors.systemGrey),
          ],
        ),
      ),
    );
  }
}

/// Site da empresa, logo abaixo das ações.
class _SiteLink extends StatelessWidget {
  const _SiteLink({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('site-empresa'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final uri = Uri.tryParse(url);
        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CupertinoColors.systemGrey4),
        ),
        child: Row(
          children: [
            const Icon(CupertinoIcons.globe,
                size: 18, color: CupertinoColors.activeBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(displaySite(url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.activeBlue)),
            ),
            const Icon(CupertinoIcons.arrow_up_right,
                size: 14, color: CupertinoColors.activeBlue),
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
      await ref.read(crmServiceProvider).addNoteToCompany(
            cnpj: widget.company.cnpj ?? '',
            noteText: text,
          );
      ref.invalidate(crmNotesProvider(widget.company.cnpj ?? ''));
      if (mounted) {
        setState(() {
          _success = true;
          _loading = false;
        });
      }
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
        color: CupertinoColors.black,
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
                    color: CupertinoColors.systemGrey,
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
                    color: CupertinoColors.white),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: _controller,
                placeholder: 'Digite a observação...',
                maxLines: 5,
                minLines: 4,
                padding: const EdgeInsets.all(12),
                style: const TextStyle(color: CupertinoColors.white),
                placeholderStyle:
                    const TextStyle(color: CupertinoColors.systemGrey2),
                decoration: BoxDecoration(
                  color: CupertinoColors.darkBackgroundGray,
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
                    color: CupertinoColors.systemGreen.withValues(alpha: 0.12),
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
                        color: CupertinoColors.darkBackgroundGray,
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed:
                            _loading ? null : () => Navigator.pop(context),
                        child: const Text('Cancelar',
                            style: TextStyle(color: CupertinoColors.white)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton.filled(
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed: _loading ? null : _save,
                        child: _loading
                            ? const CupertinoActivityIndicator()
                            : const Text(
                                'Salvar',
                                style: TextStyle(fontWeight: FontWeight.w600),
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
      await ref.read(crmServiceProvider).addContactToCompany(
            cnpj: widget.company.cnpj ?? '',
            nome: nome,
            telefone: telefone,
            email: email.isEmpty ? null : email,
          );
      ref.invalidate(crmContactsProvider(widget.company.cnpj ?? ''));
      if (mounted) {
        setState(() {
          _success = true;
          _loading = false;
        });
      }
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
      style: const TextStyle(color: CupertinoColors.white),
      placeholderStyle: const TextStyle(color: CupertinoColors.systemGrey2),
      decoration: BoxDecoration(
        color: CupertinoColors.darkBackgroundGray,
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
        color: CupertinoColors.black,
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
                    color: CupertinoColors.systemGrey,
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
                    color: CupertinoColors.white),
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
                    color: CupertinoColors.systemGreen.withValues(alpha: 0.12),
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
                        color: CupertinoColors.darkBackgroundGray,
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed:
                            _loading ? null : () => Navigator.pop(context),
                        child: const Text('Cancelar',
                            style: TextStyle(color: CupertinoColors.white)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CupertinoButton.filled(
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed: _loading ? null : _save,
                        child: _loading
                            ? const CupertinoActivityIndicator()
                            : const Text(
                                'Salvar',
                                style: TextStyle(fontWeight: FontWeight.w600),
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
