import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/konekta_theme.dart';
import '../../shared_widgets/konekta_logo.dart';
import '../../shared_widgets/password_field.dart';
import 'auth_validators.dart';
import 'register_screen.dart';
import 'role_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  late final TapGestureRecognizer _registerTapRecognizer;

  bool _isSubmitting = false;
  String? _phoneError;
  String? _passwordError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _registerTapRecognizer = TapGestureRecognizer()..onTap = _goToRegister;
    _phoneFocus.addListener(() {
      if (!_phoneFocus.hasFocus) {
        setState(() => _phoneError = validatePhoneNumber(_phoneController.text.trim()));
      }
    });
    _passwordFocus.addListener(() {
      if (!_passwordFocus.hasFocus && _passwordController.text.isEmpty) {
        setState(() => _passwordError = 'Kata sandi wajib diisi');
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _registerTapRecognizer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phoneError = validatePhoneNumber(_phoneController.text.trim());
    final passwordError = _passwordController.text.isEmpty ? 'Kata sandi wajib diisi' : null;
    setState(() {
      _phoneError = phoneError;
      _passwordError = passwordError;
      _formError = null;
    });
    if (phoneError != null || passwordError != null) return;

    setState(() => _isSubmitting = true);
    try {
      final result = await widget.apiClient.login(
        phoneNumber: '+62${_phoneController.text.trim()}',
        password: _passwordController.text,
      );
      if (!mounted) return;
      routeByRole(context, result);
    } catch (e) {
      setState(() => _formError = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _goToRegister() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegisterScreen(apiClient: widget.apiClient),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.containerMargin,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl * 2),
              const Center(
                child: KonektaLogo(width: 200),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text('Nomor Telepon', style: AppTextStyles.bodyMd),
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(AppRadius.standard),
                      border: Border.all(color: AppColors.inputFillBorder),
                    ),
                    child: const Text('+62', style: AppTextStyles.bodyMd),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      focusNode: _phoneFocus,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(12),
                      ],
                      onChanged: (_) {
                        if (_phoneError != null) setState(() => _phoneError = null);
                      },
                      decoration: InputDecoration(errorText: _phoneError),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text('Kata Sandi', style: AppTextStyles.bodyMd),
              const SizedBox(height: AppSpacing.xs),
              PasswordField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                onChanged: (_) {
                  if (_passwordError != null) setState(() => _passwordError = null);
                },
                onSubmitted: (_) => _submit(),
                errorText: _passwordError,
              ),
              if (_formError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _formError!,
                  style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
                ),
              ],
              const Spacer(),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: Text(_isSubmitting ? 'Memuat...' : 'Masuk'),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: RichText(
                  text: TextSpan(
                    style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurface),
                    children: [
                      const TextSpan(text: 'Belum punya akun? '),
                      TextSpan(
                        text: 'Daftar',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: _isSubmitting ? null : _registerTapRecognizer,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
