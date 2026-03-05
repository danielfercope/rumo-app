// lib/features/auth/register_page.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../map/providers/auth_provider.dart';

const _departments = ['Executivo', 'Gestão', 'Pré-vendas', 'Administração Interna'];

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _selectedDepartment;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showLoadingDialog() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CupertinoActivityIndicator(radius: 15),
      ),
    );
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showError('Preencha todos os campos.');
      return;
    }
    if (_selectedDepartment == null) {
      _showError('Selecione um departamento.');
      return;
    }
    if (password != confirm) {
      _showError('As senhas não coincidem.');
      return;
    }
    if (password.length < 6) {
      _showError('A senha deve ter ao menos 6 caracteres.');
      return;
    }

    setState(() => _isLoading = true);
    _showLoadingDialog();

    try {
      await ref.read(authControllerProvider).signUp(
            name: name,
            email: email,
            password: password,
            department: _selectedDepartment!,
          );

      if (!mounted) return;
      Navigator.pop(context); // Fecha o loading dialog

      _showSuccess('Bem vindo à RUMO');
    } on AuthException catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Fecha o loading dialog
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Fecha o loading dialog
      _showSuccess(
        'Você será direcionado para o app. ',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Atenção'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Sucesso'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context); // Volta para a tela de login
            },
          ),
        ],
      ),
    );
  }

  void _showDepartmentPicker() {
    int tempIndex = _selectedDepartment != null ? _departments.indexOf(_selectedDepartment!) : 0;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 280,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
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
                  child: const Text('Confirmar'),
                  onPressed: () {
                    setState(() => _selectedDepartment = _departments[tempIndex]);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(
                  initialItem: tempIndex,
                ),
                itemExtent: 40,
                onSelectedItemChanged: (index) => tempIndex = index,
                children: _departments.map((d) => Center(child: Text(d))).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String placeholder,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    bool obscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscure,
      autocorrect: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      prefix: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Icon(icon, color: CupertinoColors.systemGrey, size: 20),
      ),
      suffix: onToggleObscure != null
          ? GestureDetector(
              onTap: onToggleObscure,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  color: CupertinoColors.systemGrey,
                  size: 20,
                ),
              ),
            )
          : null,
      decoration: BoxDecoration(
        color: CupertinoColors.darkBackgroundGray,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CupertinoColors.systemGrey4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Criar Conta'),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Center(
                child: Image.asset(
                  'assets/Save_Co._Simbolo_outline_amarelo_escuro.png',
                  height: 200,
                  width: 200,
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _nameController,
                placeholder: 'Nome completo',
                icon: CupertinoIcons.person,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _emailController,
                placeholder: 'E-mail',
                icon: CupertinoIcons.mail,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              const Text(
                'Departamento',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showDepartmentPicker,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.darkBackgroundGray,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CupertinoColors.systemGrey4),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(
                          CupertinoIcons.building_2_fill,
                          color: CupertinoColors.systemGrey,
                          size: 20,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _selectedDepartment ?? 'Selecione um departamento',
                          style: TextStyle(
                            color: _selectedDepartment != null ? CupertinoColors.label : CupertinoColors.placeholderText,
                          ),
                        ),
                      ),
                      const Icon(
                        CupertinoIcons.chevron_up_chevron_down,
                        color: CupertinoColors.systemGrey,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _passwordController,
                placeholder: 'Senha',
                icon: CupertinoIcons.lock,
                obscure: _obscurePassword,
                onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _confirmPasswordController,
                placeholder: 'Confirmar senha',
                icon: CupertinoIcons.lock_shield,
                obscure: _obscureConfirm,
                textInputAction: TextInputAction.done,
                onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  onPressed: _isLoading ? null : _handleRegister,
                  child: const Text('Criar Conta'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Já tenho uma conta'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
