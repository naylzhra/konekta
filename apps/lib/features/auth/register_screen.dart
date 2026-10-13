import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/konekta_theme.dart';
import '../../shared_widgets/password_field.dart';
import 'auth_validators.dart';
import 'role_router.dart';

const _roleOptions = {
  'Pengemudi': 'driver',
  'Penumpang': 'passenger',
  'Pemerintah': 'government',
};

// TODO: add specific role form field
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  int _step = 0;
  String? _selectedRoleLabel;
  bool _isSubmitting = false;
  String? _formError;
  String? _phoneError;
  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void initState() {
    super.initState();
    _phoneFocus.addListener(() {
      if (!_phoneFocus.hasFocus) {
        setState(() => _phoneError = validatePhoneNumber(_phoneController.text.trim()));
      }
    });
    _passwordFocus.addListener(() {
      if (!_passwordFocus.hasFocus) {
        setState(() => _passwordError = validatePassword(_passwordController.text));
      }
    });
    _confirmPasswordFocus.addListener(() {
      if (!_confirmPasswordFocus.hasFocus) {
        setState(() {
          _confirmPasswordError = validatePasswordConfirmation(
            _passwordController.text,
            _confirmPasswordController.text,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _step -= 1;
      _formError = null;
    });
  }

  void _next() {
    setState(() => _formError = null);

    if (_step == 0) {
      final error = validatePhoneNumber(_phoneController.text.trim());
      setState(() => _phoneError = error);
      if (error != null) return;
      setState(() => _step = 1);
      return;
    }

    if (_step == 1) {
      final passwordError = validatePassword(_passwordController.text);
      final confirmError = validatePasswordConfirmation(
        _passwordController.text,
        _confirmPasswordController.text,
      );
      setState(() {
        _passwordError = passwordError;
        _confirmPasswordError = confirmError;
      });
      if (passwordError != null || confirmError != null) return;
      setState(() => _step = 2);
      return;
    }

    _submit();
  }

  Future<void> _submit() async {
    if (_selectedRoleLabel == null) {
      setState(() => _formError = 'Pilih jenis pengguna');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    try {
      final result = await widget.apiClient.register(
        phoneNumber: '+62${_phoneController.text.trim()}',
        password: _passwordController.text,
        role: _roleOptions[_selectedRoleLabel]!,
      );
      if (!mounted) return;
      routeByRole(context, result);
    } catch (e) {
      setState(() => _formError = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  IconButton(
                    onPressed: _isSubmitting ? null : _back,
                    icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text('Daftar', style: AppTextStyles.headlineLg),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(child: _buildStep()),
              if (_formError != null) ...[
                Text(
                  _formError!,
                  style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              ElevatedButton(
                onPressed: _isSubmitting ? null : _next,
                child: Text(_isSubmitting
                    ? 'Memuat...'
                    : (_step == 2 ? 'Daftar' : 'Lanjut')),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _PhoneStep(
          phoneController: _phoneController,
          focusNode: _phoneFocus,
          errorText: _phoneError,
          onChanged: () {
            if (_phoneError != null) setState(() => _phoneError = null);
          },
        );
      case 1:
        return _PasswordStep(
          passwordController: _passwordController,
          confirmPasswordController: _confirmPasswordController,
          passwordFocus: _passwordFocus,
          confirmPasswordFocus: _confirmPasswordFocus,
          passwordError: _passwordError,
          confirmPasswordError: _confirmPasswordError,
          onPasswordChanged: () {
            if (_passwordError != null) setState(() => _passwordError = null);
          },
          onConfirmPasswordChanged: () {
            if (_confirmPasswordError != null) setState(() => _confirmPasswordError = null);
          },
        );
      default:
        return _RoleStep(
          selectedLabel: _selectedRoleLabel,
          onChanged: (label) => setState(() => _selectedRoleLabel = label),
        );
    }
  }
}

class _PhoneStep extends StatelessWidget {
  const _PhoneStep({
    required this.phoneController,
    required this.focusNode,
    required this.errorText,
    required this.onChanged,
  });

  final TextEditingController phoneController;
  final FocusNode focusNode;
  final String? errorText;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                controller: phoneController,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                autofocus: true,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(errorText: errorText),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    required this.passwordController,
    required this.confirmPasswordController,
    required this.passwordFocus,
    required this.confirmPasswordFocus,
    required this.passwordError,
    required this.confirmPasswordError,
    required this.onPasswordChanged,
    required this.onConfirmPasswordChanged,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final FocusNode passwordFocus;
  final FocusNode confirmPasswordFocus;
  final String? passwordError;
  final String? confirmPasswordError;
  final VoidCallback onPasswordChanged;
  final VoidCallback onConfirmPasswordChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Kata Sandi', style: AppTextStyles.bodyMd),
        const SizedBox(height: AppSpacing.xs),
        PasswordField(
          controller: passwordController,
          focusNode: passwordFocus,
          autofocus: true,
          onChanged: (_) => onPasswordChanged(),
          errorText: passwordError,
          helperText: 'Minimal 8 karakter, ada angka dan karakter spesial',
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Ulangi Kata Sandi', style: AppTextStyles.bodyMd),
        const SizedBox(height: AppSpacing.xs),
        PasswordField(
          controller: confirmPasswordController,
          focusNode: confirmPasswordFocus,
          onChanged: (_) => onConfirmPasswordChanged(),
          errorText: confirmPasswordError,
        ),
      ],
    );
  }
}

class _RoleStep extends StatelessWidget {
  const _RoleStep({required this.selectedLabel, required this.onChanged});

  final String? selectedLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Jenis Pengguna', style: AppTextStyles.bodyMd),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          initialValue: selectedLabel,
          hint: const Text('Pilih jenis pengguna'),
          items: _roleOptions.keys
              .map((label) => DropdownMenuItem(value: label, child: Text(label)))
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ],
    );
  }
}
