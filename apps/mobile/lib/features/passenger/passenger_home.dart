import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';

// TODO: replace with real passenger flow (request ride, view virtual stop,
// track assigned feeder) once those APIs exist.
class PassengerHome extends StatefulWidget {
  const PassengerHome({super.key});

  @override
  State<PassengerHome> createState() => _PassengerHomeState();
}

class _PassengerHomeState extends State<PassengerHome> {
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
      appBar: AppBar(title: const Text('Passenger')),
      body: Center(child: Text(_status)),
    );
  }
}
