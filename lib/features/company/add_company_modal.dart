import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../map/providers/location_provider.dart';
import '../map/providers/profile_provider.dart';
import 'constants.dart';
import 'registration_service.dart';

class AddCompanyModal extends ConsumerStatefulWidget {
  const AddCompanyModal({super.key});

  @override
  ConsumerState<AddCompanyModal> createState() => _AddCompanyModalState();
}

class _AddCompanyModalState extends ConsumerState<AddCompanyModal> {
  int _step = 1;
  bool _loading = false;
  String? _errorMessage;

  // Dados retornados pela API EmpresaAqui
  Map<String, dynamic>? _dadosApi;
  double? _empresaLat;
  double? _empresaLon;
  String? _precisao;

  // Campos do step 1
  final _cnpjController = TextEditingController();

  // Campos do step 2
  late TextEditingController _primeiroNomeCtrl;
  late TextEditingController _nomeCompletoCtrl;
  late TextEditingController _sobrenomeCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _telefoneCtrl;
  late TextEditingController _nomeSocioCtrl;
  late TextEditingController _nomeProprietarioCtrl;

  String? _procuracao;
  String? _possuiDebitos;
  String? _valorDivida;
  String? _regimeTributario;
  String? _analises;
  String? _validadeEcac;
  String? _setorEmpresaKey;   // código HubSpot
  String? _setorEmpresaLabel; // nome em PT para exibição
  String? _departamento;
  String? _tipoLead;
  String? _prioridadeKey;

  @override
  void initState() {
    super.initState();
    _primeiroNomeCtrl = TextEditingController();
    _nomeCompletoCtrl = TextEditingController();
    _sobrenomeCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _telefoneCtrl = TextEditingController();
    _nomeSocioCtrl = TextEditingController();
    _nomeProprietarioCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _cnpjController.dispose();
    _primeiroNomeCtrl.dispose();
    _nomeCompletoCtrl.dispose();
    _sobrenomeCtrl.dispose();
    _emailCtrl.dispose();
    _telefoneCtrl.dispose();
    _nomeSocioCtrl.dispose();
    _nomeProprietarioCtrl.dispose();
    super.dispose();
  }

  String? _extractFirstSocio(Map<String, dynamic> data) {
    for (final entry in data.entries) {
      if (int.tryParse(entry.key) != null && entry.value is Map) {
        return (entry.value as Map)['socios_nome'] as String?;
      }
    }
    return null;
  }

  void _populateStep2Fields() {
    final api = _dadosApi!;
    final socio = _extractFirstSocio(api) ?? '';
    final partes = socio.split(' ');

    _primeiroNomeCtrl.text = partes.isNotEmpty ? partes.first : '';
    _nomeCompletoCtrl.text = socio;
    _sobrenomeCtrl.text = partes.length > 1 ? partes.last : '';
    _emailCtrl.text = api['email'] as String? ?? '';
    final ddd = api['ddd_1'] as String? ?? '';
    final tel = api['tel_1'] as String? ?? '';
    _telefoneCtrl.text = '$ddd$tel';
    _nomeSocioCtrl.text = socio;
    _nomeProprietarioCtrl.text = socio;
  }

  Future<void> _validateCnpj() async {
    final cnpj = _cnpjController.text.replaceAll(RegExp(r'\D'), '');
    if (cnpj.length != 14) {
      setState(() => _errorMessage = 'CNPJ deve ter 14 dígitos.');
      return;
    }

    final position = ref.read(locationProvider).value;
    if (position == null) {
      setState(() =>
          _errorMessage = 'Localização não disponível. Habilite o GPS e tente novamente.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(registrationServiceProvider);

      final exists = await service.cnpjExists(cnpj);
      if (exists) {
        setState(() => _errorMessage = 'Esta empresa já está cadastrada.');
        return;
      }

      final dadosApi = await service.fetchEmpresaAqui(cnpj);

      final endereco =
          '${dadosApi['log_tipo'] ?? ''} ${dadosApi['log_nome'] ?? ''}, ${dadosApi['log_num'] ?? ''} - ${dadosApi['log_bairro'] ?? ''}, ${dadosApi['log_municipio'] ?? ''} - ${dadosApi['log_uf'] ?? ''}';

      final geo = await service.geocodeAddress(endereco);

      final within = service.isWithinProximity(
        position.latitude,
        position.longitude,
        geo.lat,
        geo.lon,
      );

      if (!within) {
        setState(() =>
            _errorMessage = 'Bloqueado: você está a mais de 2 km da empresa. Aproxime-se para cadastrá-la.');
        return;
      }

      _dadosApi = dadosApi;
      _empresaLat = geo.lat;
      _empresaLon = geo.lon;
      _precisao = geo.precisao;
      _populateStep2Fields();

      setState(() => _step = 2);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    // Valida campos obrigatórios
    final campos = <String, String?>{
      'Primeiro nome': _primeiroNomeCtrl.text.isEmpty ? null : _primeiroNomeCtrl.text,
      'Sobrenome': _sobrenomeCtrl.text.isEmpty ? null : _sobrenomeCtrl.text,
      'Email do contato': _emailCtrl.text.isEmpty ? null : _emailCtrl.text,
      'Telefone do sócio': _telefoneCtrl.text.isEmpty ? null : _telefoneCtrl.text,
      'Nome do sócio': _nomeSocioCtrl.text.isEmpty ? null : _nomeSocioCtrl.text,
      'Nome do proprietário': _nomeProprietarioCtrl.text.isEmpty ? null : _nomeProprietarioCtrl.text,
      'Procuração': _procuracao,
      'Possui débitos': _possuiDebitos,
      'Valor da dívida': _valorDivida,
      'Regime tributário': _regimeTributario,
      'Análises a serem feitas': _analises,
      'Validade e-CAC': _validadeEcac,
      'Setor da empresa': _setorEmpresaKey,
      'Departamentos': _departamento,
      'Tipo de lead': _tipoLead,
      'Prioridade': _prioridadeKey,
    };

    final ausentes = campos.entries.where((e) => e.value == null).map((e) => e.key).toList();
    if (ausentes.isNotEmpty) {
      setState(() => _errorMessage = 'Preencha: ${ausentes.join(', ')}');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(registrationServiceProvider);
      final profile = ref.read(profileProvider).value;

      await service.saveCompany(_dadosApi!, _empresaLat!, _empresaLon!, _precisao!);

      final dadosForm = {
        'primeiro_nome': _primeiroNomeCtrl.text,
        'nome_completo': _nomeCompletoCtrl.text,
        'sobrenome': _sobrenomeCtrl.text,
        'email_contato': _emailCtrl.text,
        'telefone_socio': _telefoneCtrl.text,
        'nome_socio': _nomeSocioCtrl.text,
        'nome_proprietario': _nomeProprietarioCtrl.text,
        'para_quem_procuracao_habilitada': _procuracao,
        'possui_debitos': _possuiDebitos,
        'valor_divida': _valorDivida,
        'regime_tributario': _regimeTributario,
        'analises_a_serem_feitas': _analises,
        'validade_ecac': _validadeEcac,
        'setor_empresa': _setorEmpresaKey,
        'departamentos': _departamento,
        'tipo_lead': _tipoLead,
        'prioridade': _prioridadeKey,
      };

      await service.sendToWebhook(
        _dadosApi!,
        dadosForm,
        profile?.email ?? '',
        profile?.nome ?? '',
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: CupertinoColors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildHandle(),
          _buildHeader(),
          if (_errorMessage != null) _buildError(),
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator(color: CupertinoColors.white))
                : _step == 1
                    ? _buildStep1()
                    : _buildStep2(),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() => Container(
        margin: const EdgeInsets.only(top: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey,
          borderRadius: BorderRadius.circular(10),
        ),
      );

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _step == 1 ? 'Nova Empresa' : 'Dados Complementares',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: CupertinoColors.white),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              child: const Icon(CupertinoIcons.xmark_circle_fill,
                  color: CupertinoColors.systemGrey),
            ),
          ],
        ),
      );

  Widget _buildError() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CupertinoColors.systemRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CupertinoColors.systemRed.withOpacity(0.5)),
        ),
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: CupertinoColors.systemRed, fontSize: 13),
        ),
      );

  // ─── STEP 1 ────────────────────────────────────────────────────────────────

  Widget _buildStep1() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Informe o CNPJ para buscar os dados da empresa na EmpresaAqui e validar a proximidade (máx. 2 km).',
              style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _label('CNPJ'),
            CupertinoTextField(
              controller: _cnpjController,
              placeholder: 'Somente números (14 dígitos)',
              placeholderStyle: const TextStyle(color: CupertinoColors.systemGrey2),
              style: const TextStyle(color: CupertinoColors.white),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(14),
              ],
              decoration: BoxDecoration(
                color: CupertinoColors.darkBackgroundGray,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(14),
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: _validateCnpj,
              child: const Text('Validar e Buscar'),
            ),
          ],
        ),
      );

  // ─── STEP 2 ────────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    final nomeEmpresa =
        _dadosApi?['fantasia'] as String? ?? _dadosApi?['razao'] as String? ?? '';
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // Cabeçalho informativo
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: CupertinoColors.activeBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: CupertinoColors.activeBlue.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nomeEmpresa,
                  style: const TextStyle(
                      color: CupertinoColors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              Text(_dadosApi?['cnpj'] as String? ?? '',
                  style: const TextStyle(
                      color: CupertinoColors.systemGrey, fontSize: 12)),
            ],
          ),
        ),

        _textField('Primeiro nome', _primeiroNomeCtrl),
        _textField('Nome completo', _nomeCompletoCtrl),
        _textField('Sobrenome', _sobrenomeCtrl),
        _textField('Email do contato', _emailCtrl, keyboardType: TextInputType.emailAddress),
        _textField('Telefone do sócio', _telefoneCtrl, keyboardType: TextInputType.phone),
        _textField('Nome do sócio principal', _nomeSocioCtrl),
        _textField('Nome do proprietário', _nomeProprietarioCtrl),

        _selectField(
          'Para quem a procuração eletrônica está habilitada?',
          _procuracao,
          kProcuracoes,
          (v) => setState(() => _procuracao = v),
        ),
        _smallSelectField(
          'Possui débitos?',
          _possuiDebitos,
          const ['Sim', 'Não'],
          (v) => setState(() => _possuiDebitos = v),
        ),
        _selectField(
          'Valor da dívida',
          _valorDivida,
          kValoresDivida,
          (v) => setState(() => _valorDivida = v),
        ),
        _selectField(
          'Regime tributário',
          _regimeTributario,
          kRegimesTributarios,
          (v) => setState(() => _regimeTributario = v),
        ),
        _smallSelectField(
          'Análises a serem feitas',
          _analises,
          kAnalises,
          (v) => setState(() => _analises = v),
        ),
        _dateField(
          'Data de validade e-CAC',
          _validadeEcac,
          (v) => setState(() => _validadeEcac = v),
        ),
        _setorField(),
        _selectField(
          'Departamentos',
          _departamento,
          kDepartamentos,
          (v) => setState(() => _departamento = v),
        ),
        _smallSelectField(
          'Tipo de lead',
          _tipoLead,
          const ['Novo lead', 'Cliente da base'],
          (v) => setState(() => _tipoLead = v),
        ),
        _prioridadeField(),

        const SizedBox(height: 24),
        CupertinoButton.filled(
          onPressed: _submit,
          child: const Text('Salvar e Enviar para CRM'),
        ),
        CupertinoButton(
          onPressed: () => setState(() {
            _step = 1;
            _errorMessage = null;
          }),
          child: const Text('Voltar',
              style: TextStyle(color: CupertinoColors.systemGrey)),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ─── FIELD BUILDERS ────────────────────────────────────────────────────────

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.systemGrey)),
      );

  Widget _textField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemGrey)),
          ),
          CupertinoTextField(
            controller: controller,
            style: const TextStyle(color: CupertinoColors.white),
            keyboardType: keyboardType,
            decoration: BoxDecoration(
              color: CupertinoColors.darkBackgroundGray,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(14),
          ),
        ],
      );

  Widget _selectField(
    String label,
    String? current,
    List<String> options,
    void Function(String?) onChanged,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemGrey)),
          ),
          GestureDetector(
            onTap: () => _showSearchSheet(label, options, onChanged),
            child: _dropdownContainer(current ?? 'Selecione...', current != null),
          ),
        ],
      );

  Widget _smallSelectField(
    String label,
    String? current,
    List<String> options,
    void Function(String?) onChanged,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemGrey)),
          ),
          GestureDetector(
            onTap: () => _showActionSheet(label, options, onChanged),
            child: _dropdownContainer(current ?? 'Selecione...', current != null),
          ),
        ],
      );

  Widget _dropdownContainer(String text, bool hasValue) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: CupertinoColors.darkBackgroundGray,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: hasValue
                      ? CupertinoColors.white
                      : CupertinoColors.systemGrey2,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(CupertinoIcons.chevron_down,
                size: 14, color: CupertinoColors.systemGrey),
          ],
        ),
      );

  Widget _dateField(
    String label,
    String? current,
    void Function(String) onChanged,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemGrey)),
          ),
          GestureDetector(
            onTap: () => _showDatePicker(onChanged),
            child: _dropdownContainer(current ?? 'Selecione a data', current != null),
          ),
        ],
      );

  Widget _setorField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 14, bottom: 6),
            child: Text('Setor da empresa',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemGrey)),
          ),
          GestureDetector(
            onTap: _showSetorSheet,
            child: _dropdownContainer(
                _setorEmpresaLabel ?? 'Selecione...', _setorEmpresaKey != null),
          ),
        ],
      );

  Widget _prioridadeField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 14, bottom: 6),
            child: Text('Prioridade',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemGrey)),
          ),
          GestureDetector(
            onTap: () => _showActionSheet(
              'Prioridade',
              kPrioridades.values.toList(),
              (label) {
                if (label == null) return;
                final key = kPrioridades.entries
                    .firstWhere((e) => e.value == label)
                    .key;
                setState(() => _prioridadeKey = key);
              },
            ),
            child: _dropdownContainer(
              _prioridadeKey != null
                  ? kPrioridades[_prioridadeKey]!
                  : 'Selecione...',
              _prioridadeKey != null,
            ),
          ),
        ],
      );

  // ─── PICKERS / SHEETS ──────────────────────────────────────────────────────

  void _showSearchSheet(
    String title,
    List<String> options,
    void Function(String?) onChanged,
  ) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => _SearchSheet(
        title: title,
        options: options,
        onSelected: (v) {
          onChanged(v);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showActionSheet(
    String title,
    List<String> options,
    void Function(String?) onChanged,
  ) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: options
            .map((opt) => CupertinoActionSheetAction(
                  onPressed: () {
                    onChanged(opt);
                    Navigator.pop(ctx);
                  },
                  child: Text(opt),
                ))
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ),
    );
  }

  void _showDatePicker(void Function(String) onChanged) {
    DateTime selected = DateTime.now();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        color: CupertinoColors.darkBackgroundGray,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Cancelar'),
                  onPressed: () => Navigator.pop(ctx),
                ),
                CupertinoButton(
                  child: const Text('OK'),
                  onPressed: () {
                    final formatted =
                        '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
                    onChanged(formatted);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: DateTime.now(),
                minimumYear: 2020,
                maximumYear: 2035,
                onDateTimeChanged: (dt) => selected = dt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSetorSheet() {
    final labels = kSetores.entries.map((e) => e.value).toList();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => _SearchSheet(
        title: 'Setor da empresa',
        options: labels,
        onSelected: (label) {
          if (label != null) {
            final key = kSetores.entries
                .firstWhere((e) => e.value == label)
                .key;
            setState(() {
              _setorEmpresaKey = key;
              _setorEmpresaLabel = label;
            });
          }
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ─── SEARCH SHEET (reutilizável neste arquivo) ─────────────────────────────

class _SearchSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final void Function(String?) onSelected;

  const _SearchSheet({
    required this.title,
    required this.options,
    required this.onSelected,
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late List<String> _filtered;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = widget.options;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _filter(String q) {
    setState(() {
      _filtered = q.isEmpty
          ? widget.options
          : widget.options
              .where((o) => o.toLowerCase().contains(q.toLowerCase()))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      color: CupertinoColors.black,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('Fechar'),
                    onPressed: () => widget.onSelected(null),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoSearchTextField(
                controller: _ctrl,
                placeholder: 'Buscar...',
                style: const TextStyle(color: CupertinoColors.white),
                onChanged: _filter,
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final opt = _filtered[i];
                  return GestureDetector(
                    onTap: () => widget.onSelected(opt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: CupertinoColors.darkBackgroundGray)),
                      ),
                      child: Text(opt,
                          style: const TextStyle(
                              color: CupertinoColors.white, fontSize: 15)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
