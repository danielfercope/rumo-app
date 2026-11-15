import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../map/providers/location_provider.dart';
import '../groups/providers/group_provider.dart';
import 'crm_service.dart';
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

  // Dados cadastrais retornados pela consulta de CNPJ
  Map<String, dynamic>? _dadosApi;
  double? _empresaLat;
  double? _empresaLon;
  String? _precisao;

  // Campos do step 1
  final _cnpjController = TextEditingController();

  // Campos do step 2: o responsável pela empresa
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();

  @override
  void dispose() {
    _cnpjController.dispose();
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    _telefoneCtrl.dispose();
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

  /// Pré-preenche com o 1º sócio e o contato da Receita; o usuário corrige.
  void _populateStep2Fields() {
    final api = _dadosApi!;
    _nomeCtrl.text = _extractFirstSocio(api) ?? '';
    _emailCtrl.text = api['email'] as String? ?? '';
    final ddd = api['ddd_1'] as String? ?? '';
    final tel = api['tel_1'] as String? ?? '';
    _telefoneCtrl.text = '$ddd$tel';
  }

  Future<void> _validateCnpj() async {
    final cnpj = _cnpjController.text.replaceAll(RegExp(r'\D'), '');
    if (cnpj.length != 14) {
      setState(() => _errorMessage = 'CNPJ deve ter 14 dígitos.');
      return;
    }

    final position = ref.read(locationProvider).value;
    if (position == null) {
      setState(() => _errorMessage =
          'Localização não disponível. Habilite o GPS e tente novamente.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(registrationServiceProvider);
      final groupId = ref.read(activeGroupProvider)?.group.id;
      if (groupId == null) {
        setState(() => _errorMessage =
            'Entre em uma organização para cadastrar empresas.');
        return;
      }

      final exists = await service.cnpjInPortfolio(groupId, cnpj);
      if (exists) {
        setState(() => _errorMessage =
            'Esta empresa já está na carteira da sua organização.');
        return;
      }

      final dadosApi = await service.fetchCompanyData(cnpj);

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
        setState(() => _errorMessage =
            'Bloqueado: você está a mais de 2 km da empresa. Aproxime-se para cadastrá-la.');
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
    final nome = _nomeCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final telefone = _telefoneCtrl.text.trim();
    final ausentes = [
      if (nome.isEmpty) 'Nome completo do responsável',
      if (telefone.isEmpty) 'Telefone',
      if (email.isEmpty) 'E-mail',
    ];
    if (ausentes.isNotEmpty) {
      setState(() => _errorMessage = 'Preencha: ${ausentes.join(', ')}');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _errorMessage = 'E-mail inválido.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(registrationServiceProvider);
      final groupId = ref.read(activeGroupProvider)?.group.id;
      if (groupId == null) {
        setState(() => _errorMessage =
            'Entre em uma organização para cadastrar empresas.');
        return;
      }

      // 1) carteira da organização. Repetir é seguro: a RPC não duplica.
      await service.saveCompany(
          groupId, _dadosApi!, _empresaLat!, _empresaLon!, _precisao!);

      // 2) CRM da organização: o responsável vira contato da empresa, e o
      // Backend cria a empresa no CRM se ela ainda não estiver lá. Não existe
      // CRM global: tudo vai para o que a organização conectou.
      try {
        await ref.read(crmServiceProvider).addContactToCompany(
              cnpj: _dadosApi!['cnpj'] as String,
              nome: nome,
              telefone: telefone,
              email: email,
            );
      } catch (e) {
        setState(() => _errorMessage =
            'A empresa foi salva na carteira, mas não chegou ao CRM: $e\n'
            'Toque em "Salvar e Enviar para CRM" de novo para reenviar.');
        return;
      }

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
                ? const Center(
                    child: CupertinoActivityIndicator(
                        color: CupertinoColors.white))
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
              _step == 1 ? 'Nova Empresa' : 'Responsável',
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
          color: CupertinoColors.systemRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: CupertinoColors.systemRed.withValues(alpha: 0.5)),
        ),
        child: Text(
          _errorMessage!,
          style:
              const TextStyle(color: CupertinoColors.systemRed, fontSize: 13),
        ),
      );

  // ─── STEP 1 ────────────────────────────────────────────────────────────────

  Widget _buildStep1() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Informe o CNPJ para buscar os dados da empresa e validar a proximidade (máx. 2 km).',
              style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _label('CNPJ'),
            CupertinoTextField(
              controller: _cnpjController,
              placeholder: 'Somente números (14 dígitos)',
              placeholderStyle:
                  const TextStyle(color: CupertinoColors.systemGrey2),
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
    final nomeEmpresa = _dadosApi?['fantasia'] as String? ??
        _dadosApi?['razao'] as String? ??
        '';
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // Cabeçalho informativo
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: CupertinoColors.activeBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: CupertinoColors.activeBlue.withValues(alpha: 0.3)),
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

        _textField('Nome completo do responsável', _nomeCtrl,
            capitalization: TextCapitalization.words),
        _textField('Telefone', _telefoneCtrl,
            keyboardType: TextInputType.phone),
        _textField('E-mail', _emailCtrl,
            keyboardType: TextInputType.emailAddress),

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
    TextCapitalization capitalization = TextCapitalization.none,
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
            textCapitalization: capitalization,
            decoration: BoxDecoration(
              color: CupertinoColors.darkBackgroundGray,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(14),
          ),
        ],
      );
}
