import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';

// TODO: replace with real driver flow (accept assignment, navigate to
// virtual stop, mark passengers picked up) once those APIs exist.
class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final _apiClient = ApiClient();
  String _status = 'checking gateway...';

  @override
  void initState() {
    super.initState();
    _checkGateway();
  }

  Future<void> _checkGateway() async {
    try {
      final health = await _apiClient.checkHealth();
      if (!mounted) return;
      setState(() => _status = 'gateway: ${health['status']}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'gateway unreachable');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver')),
      body: Center(child: Text(_status)),
    );
  }
}
