import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rumo_app/features/auth/register_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../map/providers/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showError('Preencha e-mail e senha.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authControllerProvider).signIn(
            email: email,
            password: password,
          );
    } on AuthException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showError('Ocorreu um erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);
    try {
      await ref.read(authControllerProvider).signInWithGoogle();
    } catch (e) {
      if (!mounted) return;
      _showError('Falha ao entrar com Google. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _showError(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Erro no Login'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Image.asset(
                  'assets/Save_Co._Simbolo_outline_amarelo_escuro.png',
                  height: 200,
                  width: 200,
                ),
                const SizedBox(height: 20),
                const Text(
                  'RUMO',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 48),

                CupertinoTextField(
                  controller: _emailController,
                  placeholder: 'E-mail',
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(CupertinoIcons.mail, color: CupertinoColors.systemGrey, size: 20),
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.darkBackgroundGray,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CupertinoColors.systemGrey4),
                  ),
                ),
                const SizedBox(height: 12),

                CupertinoTextField(
                  controller: _passwordController,
                  placeholder: 'Senha',
                  obscureText: _obscurePassword,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(CupertinoIcons.lock, color: CupertinoColors.systemGrey, size: 20),
                  ),
                  suffix: GestureDetector(
                    onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        _obscurePassword ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                        color: CupertinoColors.systemGrey,
                        size: 20,
                      ),
                    ),
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.darkBackgroundGray,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: CupertinoColors.systemGrey4),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _isLoading || _isGoogleLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                        : const Text('Entrar'),
                  ),
                ),
                
                const SizedBox(height: 16),
                const Text('ou', style: TextStyle(color: CupertinoColors.systemGrey)),
                const SizedBox(height: 16),

                // Botão de Login com Google usando flutter_svg
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: CupertinoColors.white,
                    onPressed: _isLoading || _isGoogleLoading ? null : _handleGoogleLogin,
                    padding: EdgeInsets.zero,
                    child: _isGoogleLoading
                        ? const CupertinoActivityIndicator()
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SvgPicture.network(
                                'https://authjs.dev/img/providers/google.svg',
                                height: 20,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Entrar com Google',
                                style: TextStyle(color: CupertinoColors.black),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 24),
                Center(
                  child: CupertinoButton(
                    onPressed: () => Navigator.push(
                      context,
                      CupertinoPageRoute(builder: (_) => const RegisterPage()),
                    ),
                    child: const Text('Criar conta'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
