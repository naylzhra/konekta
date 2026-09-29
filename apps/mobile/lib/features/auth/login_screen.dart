import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../driver/driver_home.dart';
import '../government/government_home.dart';
import '../passenger/passenger_home.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isRegisterMode = false;
  String _registerRole = 'passenger';
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = _isRegisterMode
          ? await widget.apiClient.register(
              phoneNumber: _phoneController.text.trim(),
              password: _passwordController.text,
              role: _registerRole,
            )
          : await widget.apiClient.login(
              phoneNumber: _phoneController.text.trim(),
              password: _passwordController.text,
            );

      if (!mounted) return;
      _routeByRole(result);
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Could not reach gateway: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // page mapping by role
  void _routeByRole(AuthResult result) {
    switch (result.role) {
      case 'passenger':
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PassengerHome(token: result.token),
          ),
        );
        return;
      case 'driver':
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DriverHome(token: result.token),
          ),
        );
        return;
      case 'government':
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => GovernmentHome(token: result.token),
          ),
        );
        return;
      default:
        _showUnsupportedRoleDialog(
          'Role "${result.role}" is not supported in the mobile app.',
        );
    }
  }

  void _showUnsupportedRoleDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wrong app for this account'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KONEKTA')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (_isRegisterMode) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _registerRole,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'passenger', child: Text('Passenger')),
                      DropdownMenuItem(value: 'driver', child: Text('Driver')),
                      DropdownMenuItem(value: 'government', child: Text('Government')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _registerRole = value);
                    },
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: Text(_isSubmitting
                      ? 'Please wait...'
                      : (_isRegisterMode ? 'Register' : 'Login')),
                ),
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() {
                            _isRegisterMode = !_isRegisterMode;
                            _errorMessage = null;
                          }),
                  child: Text(_isRegisterMode
                      ? 'Already have an account? Login'
                      : "Don't have an account? Register"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
