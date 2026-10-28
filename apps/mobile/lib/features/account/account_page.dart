import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/strings/account_strings.dart';
import '../../core/theme/konekta_theme.dart';
import '../auth/auth_validators.dart';
import '../auth/login_screen.dart';

class AccountPage extends StatefulWidget {
  const AccountPage(
      {super.key,
      required this.token,
      required this.role,
      this.feederLabel,
      this.beforeLogout});

  final String token;
  final String role;
  final String? feederLabel;
  final Future<void> Function()? beforeLogout;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _api = ApiClient();
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await _api.send('GET', '/auth/me', token: widget.token);
      if (!response.isSuccess || response.body is! Map<String, dynamic>) {
        throw Exception();
      }
      if (mounted) {
        setState(() => _profile = response.body as Map<String, dynamic>);
      }
    } catch (_) {
      if (mounted) setState(() => _profile = null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _editProfile() async {
    final profile = _profile;
    if (profile == null) return;
    final name =
        TextEditingController(text: profile['display_name'] as String? ?? '');
    final phone = TextEditingController(
        text: (profile['phone_number'] as String? ?? '')
            .replaceFirst(RegExp(r'^\+62'), ''));
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AccountStrings.edit),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
                controller: name,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nama tampilan')),
            TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Nomor telepon', prefixText: '+62 '),
                validator: (value) => validatePhoneNumber(value?.trim() ?? '')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Simpan')),
        ],
      ),
    );
    if (saved == true) {
      setState(() => _busy = true);
      try {
        final response =
            await _api.send('PATCH', '/auth/me', token: widget.token, body: {
          'display_name': name.text.trim(),
          'phone_number': '+62${phone.text.trim()}',
        });
        if (response.statusCode == 409) {
          _message(AccountStrings.phoneTaken);
        } else if (response.isSuccess &&
            response.body is Map<String, dynamic>) {
          if (mounted) {
            setState(() => _profile = response.body as Map<String, dynamic>);
          }
          _message(AccountStrings.saved);
        } else {
          _message(AccountStrings.saveFailed);
        }
      } catch (_) {
        _message(AccountStrings.saveFailed);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    name.dispose();
    phone.dispose();
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final form = GlobalKey<FormState>();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AccountStrings.password),
        content: Form(
            key: form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  controller: current,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Kata sandi saat ini'),
                  validator: (value) =>
                      (value?.isEmpty ?? true) ? 'Wajib diisi' : null),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                  controller: next,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Kata sandi baru'),
                  validator: (value) => validatePassword(value ?? '')),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Ulangi kata sandi baru'),
                  validator: (value) =>
                      validatePasswordConfirmation(next.text, value ?? '')),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Simpan')),
        ],
      ),
    );
    if (submitted == true) {
      setState(() => _busy = true);
      try {
        final response = await _api
            .send('POST', '/auth/change-password', token: widget.token, body: {
          'current_password': current.text,
          'new_password': next.text,
        });
        _message(response.isSuccess
            ? AccountStrings.passwordChanged
            : response.statusCode == 400
                ? AccountStrings.wrongPassword
                : AccountStrings.passwordFailed);
      } catch (_) {
        _message(AccountStrings.passwordFailed);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    current.dispose();
    next.dispose();
    confirm.dispose();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text(AccountStrings.logout),
              content: const Text('Anda yakin ingin keluar dari akun ini?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Batal')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Keluar')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.beforeLogout?.call();
      await _api.logout(widget.token);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (_) => LoginScreen(apiClient: ApiClient())),
          (_) => false);
    } catch (_) {
      _message('Gagal keluar. Periksa koneksi Anda.');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (_profile?['display_name'] as String?)?.trim();
    final phone = _profile?['phone_number'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text(AccountStrings.profile)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(AccountStrings.loadFailed),
                  TextButton(
                      onPressed: _load,
                      child: const Text(AccountStrings.retry)),
                ]))
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.containerMargin),
                  children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(AppRadius.xl)),
                        child: Row(children: [
                          const CircleAvatar(
                              radius: 28,
                              backgroundColor: AppColors.primaryContainer,
                              child: Icon(Icons.person,
                                  color: AppColors.onPrimary, size: 30)),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(
                                    name == null || name.isEmpty
                                        ? AccountStrings.unnamed
                                        : name,
                                    style: AppTextStyles.headlineMd),
                                Text(
                                    widget.role == 'driver'
                                        ? AccountStrings.driver
                                        : AccountStrings.passenger,
                                    style: AppTextStyles.bodySm),
                                Text(phone, style: AppTextStyles.bodySm),
                                if (widget.feederLabel != null)
                                  Text(widget.feederLabel!,
                                      style: AppTextStyles.bodySm),
                              ])),
                        ]),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const Text(AccountStrings.account,
                          style: AppTextStyles.headlineMd),
                      const SizedBox(height: AppSpacing.xs),
                      _AccountAction(
                          icon: Icons.edit_outlined,
                          title: AccountStrings.edit,
                          onTap: _busy ? null : _editProfile),
                      _AccountAction(
                          icon: Icons.lock_outline,
                          title: AccountStrings.password,
                          onTap: _busy ? null : _changePassword),
                      _AccountAction(
                          icon: Icons.info_outline,
                          title: AccountStrings.about,
                          onTap: () => showAboutDialog(
                                  context: context,
                                  applicationName: 'KONEKTA',
                                  applicationVersion: '0.1.0',
                                  children: [
                                    const Text(AccountStrings.aboutBody)
                                  ])),
                      _AccountAction(
                          icon: Icons.help_outline,
                          title: AccountStrings.help,
                          onTap: () => showDialog<void>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                    title: const Text(AccountStrings.help),
                                    content: Text(widget.role == 'driver'
                                        ? AccountStrings.driverHelp
                                        : AccountStrings.passengerHelp),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext),
                                          child: const Text('Tutup'))
                                    ],
                                  ))),
                      const Divider(height: AppSpacing.xl),
                      _AccountAction(
                          icon: Icons.logout,
                          title: AccountStrings.logout,
                          color: AppColors.error,
                          onTap: _busy ? null : _logout),
                    ]),
    );
  }
}

class _AccountAction extends StatelessWidget {
  const _AccountAction(
      {required this.icon,
      required this.title,
      required this.onTap,
      this.color});
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color ?? AppColors.primary),
        title: Text(title, style: AppTextStyles.bodyMd.copyWith(color: color)),
        trailing: const Icon(Icons.chevron_right),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        onTap: onTap,
      );
}
