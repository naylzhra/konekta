import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/konekta_theme.dart';

// TODO: replace with real passenger home
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
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
    return Center(child: Text(_status, style: AppTextStyles.bodyMd));
  }
}
