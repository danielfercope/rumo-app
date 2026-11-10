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

  String _messageOf(Object e) => e is ApiException ? e.message : '$e';

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
    final title = switch (_step) {
      _Step.token => 'Conectar CRM · 1 de 3',
      _Step.campos => 'Conectar CRM · 2 de 3',
      _Step.previa => 'Conectar CRM · 3 de 3',
    };

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            switch (_step) {
              _Step.token => _buildTokenStep(),
              _Step.campos => _buildFieldsStep(),
              _Step.previa => _buildPreviewStep(),
            },
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  key: const ValueKey('wizard-error'),
                  style:
                      const TextStyle(color: CupertinoColors.destructiveRed)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _primaryButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton.filled(
        onPressed: _busy ? null : onPressed,
        child: _busy
            ? const CupertinoActivityIndicator(color: CupertinoColors.white)
            : Text(label),
      ),
    );
  }

  Widget _backButton(_Step to) => CupertinoButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _step = to;
                  _error = null;
                }),
        child: const Text('Voltar'),
      );

  Widget _buildTokenStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Importe sua carteira do HubSpot',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'No HubSpot, crie um token de acesso privado (Private App) com '
          'permissão somente de leitura para empresas: '
          'crm.objects.companies.read e crm.schemas.companies.read. '
          'Depois, cole o token abaixo.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Lemos apenas dados de empresas (CNPJ e estágio). Contatos, notas e '
          'negócios nunca são lidos, e o token fica guardado cifrado no servidor.',
          style: TextStyle(color: CupertinoColors.systemGrey),
        ),
        const SizedBox(height: 16),
        CupertinoTextField(
          key: const ValueKey('token-field'),
          controller: _tokenController,
          placeholder: 'Token do HubSpot',
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        _primaryButton(
          'Validar token',
          _token.isEmpty ? null : _validate,
        ),
      ],
    );
  }

  Widget _pickerRow(String label, CrmProperty? value, VoidCallback onTap,
      {Key? key}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          CupertinoButton(
            key: key,
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.centerLeft,
            onPressed: _busy ? null : onTap,
            child: Text(value == null ? 'Escolher…' : value.label),
          ),
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
        const Text(
          'Mapeie os campos',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _pickerRow(
          'Qual campo guarda o CNPJ?',
          _cnpjProp,
          () async {
            final p = await _pick('Campo do CNPJ',
                stringProps.isEmpty ? _properties : stringProps, _cnpjProp);
            if (p != null) setState(() => _cnpjProp = p);
          },
          key: const ValueKey('pick-cnpj'),
        ),
        _pickerRow(
          'Qual campo guarda o estágio do cliente?',
          _statusProp,
          () async {
            final p = await _pick(
                'Campo do estágio',
                statusCandidates.isEmpty ? _properties : statusCandidates,
                _statusProp);
            if (p != null) setState(() => _selectStatusProp(p));
          },
          key: const ValueKey('pick-status'),
        ),
        if (_statusProp != null) ..._buildStatusMapping(_statusProp!),
        const SizedBox(height: 16),
        _primaryButton('Ver prévia', canContinue ? _loadPreview : null),
        Center(child: _backButton(_Step.token)),
      ],
    );
  }

  List<Widget> _buildStatusMapping(CrmProperty prop) {
    if (prop.options.isEmpty) {
      return [
        const Text('Quais valores indicam cada situação?',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        CupertinoTextField(
          key: const ValueKey('valores-cliente'),
          controller: _clienteTextController,
          placeholder: 'Cliente (valores separados por vírgula)',
          autocorrect: false,
        ),
        const SizedBox(height: 8),
        CupertinoTextField(
          key: const ValueKey('valores-perdido'),
          controller: _perdidoTextController,
          placeholder: 'Perdido (valores separados por vírgula)',
          autocorrect: false,
        ),
        const SizedBox(height: 4),
        const Text('O que não estiver em nenhuma lista é tratado como lead.',
            style: TextStyle(color: CupertinoColors.systemGrey)),
      ];
    }
    return [
      const Text('Como cada estágio deve ser tratado?',
          style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      for (final option in prop.options)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(option.label),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<String>(
                  key: ValueKey('classe-${option.value}'),
                  groupValue: _classe[option.value] ?? 'lead',
                  children: const {
                    'lead': Text('Lead'),
                    'cliente': Text('Cliente'),
                    'perdido': Text('Perdido'),
                  },
                  onValueChanged: (v) {
                    if (v != null) {
                      setState(() => _classe[option.value] = v);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildPreviewStep() {
    final p = _preview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Prévia da importação',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (p.validos == 0)
          const Text(
            'Nenhuma empresa com CNPJ válido foi encontrada. Volte e confira '
            'o campo escolhido para o CNPJ.',
            key: ValueKey('previa-vazia'),
            style: TextStyle(color: CupertinoColors.destructiveRed),
          )
        else ...[
          Text('Encontramos ${p.validos} empresas com CNPJ válido:',
              key: const ValueKey('previa-total')),
          const SizedBox(height: 8),
          Text('• ${p.clientes} clientes'),
          Text('• ${p.leads} leads'),
          Text('• ${p.perdidos} perdidas'),
        ],
        if (p.cnpjInvalido > 0) ...[
          const SizedBox(height: 8),
          Text('${p.cnpjInvalido} empresas serão ignoradas por CNPJ inválido.',
              style: const TextStyle(color: CupertinoColors.systemGrey)),
        ],
        if (p.truncado) ...[
          const SizedBox(height: 8),
          const Text(
            'Sua base é grande: a prévia considera só as primeiras 5.000 '
            'empresas, mas a importação lê todas.',
            style: TextStyle(color: CupertinoColors.systemGrey),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'A importação roda em segundo plano. As empresas aparecem no mapa '
          'quando ela terminar.',
        ),
        const SizedBox(height: 16),
        _primaryButton('Conectar e importar', p.validos == 0 ? null : _connect),
        Center(child: _backButton(_Step.campos)),
      ],
    );
  }
}
