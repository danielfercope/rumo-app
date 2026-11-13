import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../models/crm_models.dart';
import '../providers/carteira_provider.dart';

enum _Step { token, campos, previa }

const _valoresClientePadrao = {'customer', 'evangelist'};

/// Assistente de conexão com o CRM: token → campos → prévia → conectar.
/// Fecha com `true` quando a conexão foi gravada (a carga inicial segue em
/// segundo plano no servidor). O token vive só neste State, em memória: nunca é
/// persistido nem logado no app.
class CrmConnectionWizard extends ConsumerStatefulWidget {
  const CrmConnectionWizard({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<CrmConnectionWizard> createState() =>
      _CrmConnectionWizardState();
}

class _CrmConnectionWizardState extends ConsumerState<CrmConnectionWizard> {
  final _tokenController = TextEditingController();
  final _clienteTextController = TextEditingController();
  final _perdidoTextController = TextEditingController();

  _Step _step = _Step.token;
  bool _busy = false;
  bool _showToken = false;
  String? _error;

  List<CrmProperty> _properties = [];
  CrmProperty? _cnpjProp;
  CrmProperty? _statusProp;
  // valor do estágio -> 'lead' | 'cliente' | 'perdido'
  Map<String, String> _classe = {};
  CrmPreview? _preview;

  @override
  void dispose() {
    _tokenController.dispose();
    _clienteTextController.dispose();
    _perdidoTextController.dispose();
    super.dispose();
  }

  String get _token => _tokenController.text.trim();

  String _messageOf(Object e) {
    if (e is ApiException) return e.message;
    final text = '$e';
    // Falha de rede/CORS: o texto cru ("ClientException: Failed to fetch…") não
    // ajuda ninguém. O detalhe técnico vai pro console.
    if (text.contains('Failed to fetch') ||
        text.contains('SocketException') ||
        text.contains('ClientException')) {
      debugPrint('Falha de rede no assistente do CRM: $text');
      return 'Não foi possível falar com o servidor. Confira sua conexão e '
          'tente de novo.';
    }
    return text;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = _messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Passo 1: token ────────────────────────────────────────────────

  Future<void> _validate() => _run(() async {
        final props = await ref
            .read(carteiraServiceProvider)
            .validar(widget.groupId, _token);
        if (!mounted) return;
        _properties = props;
        _cnpjProp = props.cast<CrmProperty?>().firstWhere(
              (p) =>
                  p!.name.toLowerCase().contains('cnpj') ||
                  p.label.toLowerCase().contains('cnpj'),
              orElse: () => null,
            );
        _selectStatusProp(
          props.cast<CrmProperty?>().firstWhere(
                (p) => p!.name == 'lifecyclestage',
                orElse: () => props.cast<CrmProperty?>().firstWhere(
                      (p) => p!.options.isNotEmpty,
                      orElse: () => null,
                    ),
              ),
        );
        setState(() => _step = _Step.campos);
      });

  void _selectStatusProp(CrmProperty? prop) {
    _statusProp = prop;
    _classe = {
      for (final o in prop?.options ?? const <CrmOption>[])
        o.value: _valoresClientePadrao.contains(o.value.toLowerCase())
            ? 'cliente'
            : 'lead',
    };
  }

  // ─── Passo 2: campos ───────────────────────────────────────────────

  List<String> _split(String text) =>
      text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  CrmMapping _buildMapping() {
    final hasOptions = _statusProp!.options.isNotEmpty;
    return CrmMapping(
      campoCnpj: _cnpjProp!.name,
      campoStatus: _statusProp!.name,
      valoresCliente: hasOptions
          ? [
              for (final e in _classe.entries)
                if (e.value == 'cliente') e.key
            ]
          : _split(_clienteTextController.text),
      valoresPerdido: hasOptions
          ? [
              for (final e in _classe.entries)
                if (e.value == 'perdido') e.key
            ]
          : _split(_perdidoTextController.text),
    );
  }

  Future<void> _loadPreview() => _run(() async {
        final preview = await ref
            .read(carteiraServiceProvider)
            .previa(widget.groupId, _token, _buildMapping());
        if (!mounted) return;
        setState(() {
          _preview = preview;
          _step = _Step.previa;
        });
      });

  Future<CrmProperty?> _pick(
      String title, List<CrmProperty> items, CrmProperty? current) {
    return showCupertinoModalPopup<CrmProperty>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final p in items)
            CupertinoActionSheetAction(
              isDefaultAction: p.name == current?.name,
              onPressed: () => Navigator.pop(ctx, p),
              child:
                  Text(p.label == p.name ? p.name : '${p.label} (${p.name})'),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ),
    );
  }

  // ─── Passo 3: conectar ─────────────────────────────────────────────

  Future<void> _connect() => _run(() async {
        await ref
            .read(carteiraServiceProvider)
            .conectar(widget.groupId, _token, _buildMapping());
        if (mounted) Navigator.pop(context, true);
      });

  // ─── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Conectar CRM'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
      ),
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _StepHeader(step: _step.index),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      _Step.token => _buildTokenStep(),
                      _Step.campos => _buildFieldsStep(),
                      _Step.previa => _buildPreviewStep(),
                    },
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: _error!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final onAccent = accent.computeLuminance() > 0.5
        ? CupertinoColors.black
        : CupertinoColors.white;
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton.filled(
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.symmetric(vertical: 15),
        onPressed: _busy ? null : onPressed,
        child: _busy
            ? CupertinoActivityIndicator(color: onAccent)
            : Text(label,
                style: TextStyle(
                    color: onAccent,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _backButton(_Step to) => Center(
        child: CupertinoButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _step = to;
                    _error = null;
                  }),
          child: const Text('Voltar'),
        ),
      );

  // ─── Passo 1 ───────────────────────────────────────────────────────

  Widget _buildTokenStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          icon: CupertinoIcons.link,
          title: 'Conecte o seu HubSpot',
          subtitle: 'Importe sua carteira de empresas em poucos passos.',
        ),
        const SizedBox(height: 20),
        const _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel('Como gerar o token'),
              SizedBox(height: 12),
              _NumberedStep(
                n: 1,
                text: 'No HubSpot, abra Configurações › Integrações › '
                    'Aplicativos privados e crie um app.',
              ),
              _NumberedStep(
                n: 2,
                text: 'Em Escopos, marque somente leitura de empresas:',
                chips: [
                  'crm.objects.companies.read',
                  'crm.schemas.companies.read',
                ],
              ),
              _NumberedStep(
                n: 3,
                text: 'Copie o token de acesso e cole abaixo.',
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('Token de acesso'),
              const SizedBox(height: 10),
              CupertinoTextField(
                key: const ValueKey('token-field'),
                controller: _tokenController,
                placeholder: 'Cole o token do HubSpot',
                obscureText: !_showToken,
                autocorrect: false,
                enableSuggestions: false,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(CupertinoIcons.lock_fill,
                      size: 16, color: CupertinoColors.systemGrey),
                ),
                suffix: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: Size.zero,
                  onPressed: () => setState(() => _showToken = !_showToken),
                  child: Icon(
                    _showToken
                        ? CupertinoIcons.eye_slash_fill
                        : CupertinoIcons.eye_fill,
                    size: 18,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
                decoration: BoxDecoration(
                  color:
                      CupertinoColors.tertiarySystemFill.resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              const _InfoRow(
                icon: CupertinoIcons.shield_fill,
                text: 'Lemos apenas o CNPJ e o estágio das empresas. '
                    'Contatos, notas e negócios nunca são lidos, e o token '
                    'fica guardado cifrado no servidor.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton('Validar token', _token.isEmpty ? null : _validate),
      ],
    );
  }

  // ─── Passo 2 ───────────────────────────────────────────────────────

  Widget _selectorRow(
      {required String label,
      required CrmProperty? value,
      required VoidCallback onTap,
      required Key key}) {
    return CupertinoButton(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 10),
      minimumSize: Size.zero,
      onPressed: _busy ? null : onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context))),
                const SizedBox(height: 3),
                Text(
                  value == null ? 'Escolher…' : value.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: value == null
                        ? CupertinoTheme.of(context).primaryColor
                        : CupertinoColors.label.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
          const Icon(CupertinoIcons.chevron_up_chevron_down,
              size: 16, color: CupertinoColors.systemGrey),
        ],
      ),
    );
  }

  Widget _buildFieldsStep() {
    final stringProps = _properties.where((p) => p.type == 'string').toList();
    final statusCandidates = _properties
        .where((p) => p.options.isNotEmpty || p.type == 'string')
        .toList();
    final canContinue = _cnpjProp != null && _statusProp != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          icon: CupertinoIcons.arrow_branch,
          title: 'Mapeie os campos',
          subtitle: 'Diga onde o HubSpot guarda o CNPJ e o estágio de cada '
              'empresa.',
        ),
        const SizedBox(height: 20),
        _Card(
          child: Column(
            children: [
              _selectorRow(
                label: 'Campo do CNPJ',
                value: _cnpjProp,
                key: const ValueKey('pick-cnpj'),
                onTap: () async {
                  final p = await _pick(
                      'Campo do CNPJ',
                      stringProps.isEmpty ? _properties : stringProps,
                      _cnpjProp);
                  if (p != null) setState(() => _cnpjProp = p);
                },
              ),
              const _Divider(),
              _selectorRow(
                label: 'Campo do estágio',
                value: _statusProp,
                key: const ValueKey('pick-status'),
                onTap: () async {
                  final p = await _pick(
                      'Campo do estágio',
                      statusCandidates.isEmpty ? _properties : statusCandidates,
                      _statusProp);
                  if (p != null) setState(() => _selectStatusProp(p));
                },
              ),
            ],
          ),
        ),
        if (_statusProp != null) ...[
          const SizedBox(height: 16),
          _Card(child: _buildStatusMapping(_statusProp!)),
        ],
        const SizedBox(height: 20),
        _primaryButton('Ver prévia', canContinue ? _loadPreview : null),
        _backButton(_Step.token),
      ],
    );
  }

  Widget _buildStatusMapping(CrmProperty prop) {
    if (prop.options.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Quais valores indicam cada situação?'),
          const SizedBox(height: 12),
          CupertinoTextField(
            key: const ValueKey('valores-cliente'),
            controller: _clienteTextController,
            placeholder: 'Cliente (valores separados por vírgula)',
            autocorrect: false,
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            key: const ValueKey('valores-perdido'),
            controller: _perdidoTextController,
            placeholder: 'Perdido (valores separados por vírgula)',
            autocorrect: false,
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 12),
          const _InfoRow(
            icon: CupertinoIcons.info_circle_fill,
            text: 'O que não estiver em nenhuma lista é tratado como lead.',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Como tratar cada estágio'),
        const SizedBox(height: 4),
        Text(
          'Escolha o que cada estágio do HubSpot significa pra você.',
          style: TextStyle(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context)),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < prop.options.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _stageRow(prop.options[i]),
        ],
      ],
    );
  }

  Widget _stageRow(CrmOption option) {
    final classe = _classe[option.value] ?? 'lead';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: _statusColor(classe), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(option.label,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<String>(
            key: ValueKey('classe-${option.value}'),
            groupValue: classe,
            children: const {
              'lead': Text('Lead'),
              'cliente': Text('Cliente'),
              'perdido': Text('Perdido'),
            },
            onValueChanged: (v) {
              if (v != null) setState(() => _classe[option.value] = v);
            },
          ),
        ),
      ],
    );
  }

  // ─── Passo 3 ───────────────────────────────────────────────────────

  Widget _buildPreviewStep() {
    final p = _preview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          icon: CupertinoIcons.chart_pie_fill,
          title: 'Prévia da importação',
          subtitle: 'Confira o que será trazido antes de conectar.',
        ),
        const SizedBox(height: 20),
        if (p.validos == 0)
          const _Card(
            child: _InfoRow(
              key: ValueKey('previa-vazia'),
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              color: CupertinoColors.destructiveRed,
              text: 'Nenhuma empresa com CNPJ válido foi encontrada. Volte e '
                  'confira o campo escolhido para o CNPJ.',
            ),
          )
        else
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p.validos}',
                    key: const ValueKey('previa-total'),
                    style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        height: 1.1)),
                const SizedBox(height: 2),
                Text('empresas com CNPJ válido',
                    style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context))),
                const SizedBox(height: 16),
                _DistributionBar(
                  clientes: p.clientes,
                  leads: p.leads,
                  perdidos: p.perdidos,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _StatTile(
                        key: const ValueKey('stat-clientes'),
                        label: 'Clientes',
                        value: p.clientes,
                        total: p.validos,
                        color: _statusColor('cliente')),
                    const SizedBox(width: 10),
                    _StatTile(
                        key: const ValueKey('stat-leads'),
                        label: 'Leads',
                        value: p.leads,
                        total: p.validos,
                        color: _statusColor('lead')),
                    const SizedBox(width: 10),
                    _StatTile(
                        key: const ValueKey('stat-perdidas'),
                        label: 'Perdidas',
                        value: p.perdidos,
                        total: p.validos,
                        color: _statusColor('perdido')),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.cnpjInvalido > 0) ...[
                _InfoRow(
                  icon: CupertinoIcons.exclamationmark_circle_fill,
                  color: CupertinoColors.systemOrange,
                  text: '${p.cnpjInvalido} empresas serão ignoradas por CNPJ '
                      'inválido.',
                ),
                const SizedBox(height: 12),
              ],
              if (p.truncado) ...[
                const _InfoRow(
                  icon: CupertinoIcons.info_circle_fill,
                  text: 'Sua base é grande: a prévia considera só as '
                      'primeiras 5.000 empresas, mas a importação lê todas.',
                ),
                const SizedBox(height: 12),
              ],
              const _InfoRow(
                icon: CupertinoIcons.clock_fill,
                text: 'A importação roda em segundo plano. As empresas '
                    'aparecem no mapa quando ela terminar.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton('Conectar e importar', p.validos == 0 ? null : _connect),
        _backButton(_Step.campos),
      ],
    );
  }
}

Color _statusColor(String classe) => switch (classe) {
      'cliente' => CupertinoColors.systemGreen,
      'perdido' => CupertinoColors.systemGrey,
      _ => CupertinoColors.systemBlue,
    };

// ─── Componentes ─────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground
              .resolveFrom(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: CupertinoColors.separator.resolveFrom(context),
              width: 0.5),
        ),
        child: child,
      );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        height: 0.5,
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: CupertinoColors.separator.resolveFrom(context),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600));
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: accent, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 15,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context))),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Passo N de 3" + três marcadores ligados por linhas (feito/atual/pendente).
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});
  final int step;

  static const _labels = ['Acesso', 'Campos', 'Prévia'];

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final onAccent = accent.computeLuminance() > 0.5
        ? CupertinoColors.black
        : CupertinoColors.white;
    final muted = CupertinoColors.systemGrey3.resolveFrom(context);

    Widget dot(int i) {
      final done = i < step;
      final current = i == step;
      return Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done || current ? accent : null,
          shape: BoxShape.circle,
          border: done || current ? null : Border.all(color: muted, width: 1.5),
        ),
        child: done
            ? Icon(CupertinoIcons.check_mark, size: 14, color: onAccent)
            : Text('${i + 1}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: current
                        ? onAccent
                        : CupertinoColors.secondaryLabel.resolveFrom(context))),
      );
    }

    Widget line(int i) => Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: i < step ? accent : muted,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Passo ${step + 1} de 3',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.secondaryLabel.resolveFrom(context))),
        const SizedBox(height: 10),
        Row(children: [
          for (var i = 0; i < 3; i++) ...[
            dot(i),
            const SizedBox(width: 6),
            Text(_labels[i],
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
                    color: i <= step
                        ? CupertinoColors.label.resolveFrom(context)
                        : CupertinoColors.secondaryLabel.resolveFrom(context))),
            if (i < 2) line(i),
          ],
        ]),
      ],
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep(
      {required this.n, required this.text, this.chips, this.last = false});
  final int n;
  final String text;
  final List<String>? chips;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontSize: 15, height: 1.3)),
                if (chips != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in chips!)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: CupertinoColors.tertiarySystemFill
                                .resolveFrom(context),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(c,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'Menlo',
                                  fontFamilyFallback: ['monospace'])),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {super.key, required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? CupertinoColors.systemGrey;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: c),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: color ??
                      CupertinoColors.secondaryLabel.resolveFrom(context))),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.destructiveRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: CupertinoColors.destructiveRed.withValues(alpha: 0.4),
              width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(CupertinoIcons.exclamationmark_circle_fill,
                size: 18, color: CupertinoColors.destructiveRed),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  key: const ValueKey('wizard-error'),
                  style: const TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      color: CupertinoColors.destructiveRed)),
            ),
          ],
        ),
      );
}

/// Barra única dividida em clientes/leads/perdidas, proporcional aos números.
class _DistributionBar extends StatelessWidget {
  const _DistributionBar(
      {required this.clientes, required this.leads, required this.perdidos});
  final int clientes;
  final int leads;
  final int perdidos;

  @override
  Widget build(BuildContext context) {
    final parts = [
      (clientes, _statusColor('cliente')),
      (leads, _statusColor('lead')),
      (perdidos, _statusColor('perdido')),
    ].where((e) => e.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: parts[i].$1,
                child: Container(color: parts[i].$2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });
  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (value * 100 / total).round();
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context))),
              ),
            ]),
            const SizedBox(height: 6),
            Text('$value',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text('$pct%',
                style: TextStyle(
                    fontSize: 12,
                    color:
                        CupertinoColors.secondaryLabel.resolveFrom(context))),
          ],
        ),
      ),
    );
  }
}
