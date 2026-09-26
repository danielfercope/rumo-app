import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:rumo_app/features/auth/register_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'privacy_policy_page.dart';
import 'providers/auth_provider.dart';

// Logo "G" do Google embutido localmente para não depender de uma URL externa
// (o botão de login quebrava sem rede, e falhava em testes de widget).
const _googleLogoSvg = '''
<svg width="20" height="20" viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
  <path d="M19.6 10.23c0-.82-.1-1.42-.25-2.05H10v3.72h5.5c-.15.96-.74 2.31-2.04 3.22v2.45h3.16c1.89-1.73 2.98-4.3 2.98-7.34z" fill="#4285F4"/>
  <path d="M10 20c2.7 0 4.96-.89 6.62-2.42l-3.16-2.45c-.87.59-2 .94-3.46.94-2.66 0-4.91-1.79-5.71-4.2H1.03v2.53A9.99 9.99 0 0 0 10 20z" fill="#34A853"/>
  <path d="M4.29 11.87A5.99 5.99 0 0 1 3.98 10c0-.65.11-1.28.31-1.87V5.6H1.03A9.99 9.99 0 0 0 0 10c0 1.61.39 3.14 1.03 4.4l3.26-2.53z" fill="#FBBC05"/>
  <path d="M10 3.96c1.47 0 2.79.51 3.82 1.5l2.87-2.87C14.95.99 12.7 0 10 0 6.09 0 2.71 2.24 1.03 5.6l3.26 2.53C5.09 5.72 7.34 3.96 10 3.96z" fill="#EA4335"/>
</svg>
''';

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(CupertinoIcons.mail,
                        color: CupertinoColors.systemGrey, size: 20),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Icon(CupertinoIcons.lock,
                        color: CupertinoColors.systemGrey, size: 20),
                  ),
                  suffix: GestureDetector(
                    onTap: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        _obscurePassword
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
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
                    onPressed:
                        _isLoading || _isGoogleLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const CupertinoActivityIndicator(
                            color: CupertinoColors.white)
                        : const Text('Entrar'),
                  ),
                ),

                const SizedBox(height: 16),
                const Text('ou',
                    style: TextStyle(color: CupertinoColors.systemGrey)),
                const SizedBox(height: 16),

                // Botão de Login com Google usando flutter_svg
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton(
                    color: CupertinoColors.white,
                    onPressed: _isLoading || _isGoogleLoading
                        ? null
                        : _handleGoogleLogin,
                    padding: EdgeInsets.zero,
                    child: _isGoogleLoading
                        ? const CupertinoActivityIndicator()
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SvgPicture.string(
                                _googleLogoSvg,
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
                Center(
                  child: CupertinoButton(
                    onPressed: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                          builder: (_) => const PrivacyPolicyPage()),
                    ),
                    child: const Text(
                      'Política de Privacidade',
                      style: TextStyle(
                        color: CupertinoColors.systemGrey,
                        fontSize: 13,
                      ),
                    ),
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
