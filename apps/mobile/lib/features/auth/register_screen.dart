import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/strings/live_tracking_strings.dart';
import '../../core/theme/konekta_theme.dart';
import '../live_tracking/data/feeder_api.dart';
import '../live_tracking/domain/feeder_models.dart';
import '../../shared_widgets/password_field.dart';
import 'auth_validators.dart';
import 'role_router.dart';

// Government accounts use the web dashboard (apps/dashboard) and aren't
// self-registrable.
const _roleOptions = {
  'Pengemudi': 'driver',
  'Penumpang': 'passenger',
};

const _driverRole = 'driver';

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

  // Driver-only: the feeder this account drives (DESIGN.md §5.8).
  late final _feederApi = FeederApi(widget.apiClient);
  List<CorridorOption>? _corridors;
  bool _corridorsLoading = false;
  bool _corridorsFailed = false;
  String? _selectedCorridorId;
  String? _selectedFeederId;

  bool get _isDriver => _selectedRoleLabel != null && _roleOptions[_selectedRoleLabel] == _driverRole;

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

  void _onRoleChanged(String label) {
    setState(() {
      _selectedRoleLabel = label;
      _formError = null;
    });
    if (_isDriver && _corridors == null && !_corridorsLoading) _loadCorridors();
  }

  Future<void> _loadCorridors() async {
    setState(() {
      _corridorsLoading = true;
      _corridorsFailed = false;
    });
    try {
      final corridors = await _feederApi.listCorridors();
      if (!mounted) return;
      setState(() => _corridors = corridors);
    } on FeederApiException {
      if (!mounted) return;
      setState(() => _corridorsFailed = true);
    } finally {
      if (mounted) setState(() => _corridorsLoading = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedRoleLabel == null) {
      setState(() => _formError = 'Pilih jenis pengguna');
      return;
    }
    if (_isDriver && _selectedFeederId == null) {
      setState(() => _formError = LiveTrackingStrings.chooseFeeder);
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
        feederId: _isDriver ? _selectedFeederId : null,
      );
      if (!mounted) return;
      routeByRole(context, result);
    } catch (e) {
      final feederTaken = e is AuthException && e.message.contains('Feeder not available');
      setState(() {
        _formError = friendlyAuthError(e);
        if (feederTaken) {
          // Someone else took it meanwhile; refresh the list.
          _selectedFeederId = null;
          _corridors = null;
        }
      });
      if (feederTaken) _loadCorridors();
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
              Expanded(child: SingleChildScrollView(child: _buildStep())),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RoleStep(selectedLabel: _selectedRoleLabel, onChanged: _onRoleChanged),
            if (_isDriver) ...[
              const SizedBox(height: AppSpacing.lg),
              _FeederPicker(
                corridors: _corridors,
                loading: _corridorsLoading,
                failed: _corridorsFailed,
                selectedCorridorId: _selectedCorridorId,
                selectedFeederId: _selectedFeederId,
                onRetry: _loadCorridors,
                onCorridorChanged: (id) => setState(() {
                  _selectedCorridorId = id;
                  _selectedFeederId = null;
                }),
                onFeederChanged: (id) => setState(() {
                  _selectedFeederId = id;
                  _formError = null;
                }),
              ),
            ],
          ],
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

class _FeederPicker extends StatelessWidget {
  const _FeederPicker({
    required this.corridors,
    required this.loading,
    required this.failed,
    required this.selectedCorridorId,
    required this.selectedFeederId,
    required this.onRetry,
    required this.onCorridorChanged,
    required this.onFeederChanged,
  });

  final List<CorridorOption>? corridors;
  final bool loading;
  final bool failed;
  final String? selectedCorridorId;
  final String? selectedFeederId;
  final VoidCallback onRetry;
  final ValueChanged<String> onCorridorChanged;
  final ValueChanged<String> onFeederChanged;

  @override
  Widget build(BuildContext context) {
    final corridors = this.corridors;
    if (loading) return const Center(child: CircularProgressIndicator());
    if (failed || corridors == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            LiveTrackingStrings.corridorsLoadFailed,
            style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onRetry, child: const Text(LiveTrackingStrings.retry)),
          ),
        ],
      );
    }

    final corridor = corridors.where((c) => c.id == selectedCorridorId).firstOrNull;
    final feeders = corridor?.availableFeeders ?? const <FeederOption>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(LiveTrackingStrings.corridorLabel, style: AppTextStyles.bodyMd),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          initialValue: corridor?.id,
          hint: const Text(LiveTrackingStrings.corridorHint),
          items: [for (final c in corridors) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: (value) {
            if (value != null) onCorridorChanged(value);
          },
        ),
        if (corridor != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const Text(LiveTrackingStrings.feederLabelField, style: AppTextStyles.bodyMd),
          const SizedBox(height: AppSpacing.xs),
          if (feeders.isEmpty)
            const Text(LiveTrackingStrings.noFeederAvailable, style: AppTextStyles.bodySm)
          else
            DropdownButtonFormField<String>(
              // Keyed by corridor so switching corridors resets the selection.
              key: ValueKey(corridor.id),
              initialValue: feeders.any((f) => f.id == selectedFeederId) ? selectedFeederId : null,
              hint: const Text(LiveTrackingStrings.feederHint),
              items: [
                for (final f in feeders)
                  DropdownMenuItem(value: f.id, child: Text(LiveTrackingStrings.feederOption(f.number, f.capacity))),
              ],
              onChanged: (value) {
                if (value != null) onFeederChanged(value);
              },
            ),
        ],
      ],
    );
  }
}
