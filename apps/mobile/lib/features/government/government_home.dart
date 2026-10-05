import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';


/// TODO: use real statistics
class GovernmentHome extends StatefulWidget {
  const GovernmentHome({super.key, required this.token});

  final String token;

  @override
  State<GovernmentHome> createState() => _GovernmentHomeState();
}

class _StatTile {
  const _StatTile(this.label, this.value);

  final String label;
  final String value;
}

class _GovernmentHomeState extends State<GovernmentHome> {
  final _apiClient = ApiClient();
  String _gatewayStatus = 'checking gateway...';

  // TODO: replace with real numbers from a gateway/stats endpoint.
  final List<_StatTile> _stats = const [
    _StatTile('Active feeders', '--'),
    _StatTile('Virtual stops', '--'),
    _StatTile('Rides today', '--'),
    _StatTile('Avg. wait time', '--'),
  ];

  @override
  void initState() {
    super.initState();
    _checkGateway();
  }

  Future<void> _checkGateway() async {
    try {
      final health = await _apiClient.checkHealth();
      if (!mounted) return;
      setState(() => _gatewayStatus = 'gateway: ${health['status']}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _gatewayStatus = 'gateway unreachable');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Government — Overview')),
      body: RefreshIndicator(
        onRefresh: _checkGateway,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_gatewayStatus, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: _stats.map((stat) => _StatCard(stat: stat)).toList(),
            ),
            const SizedBox(height: 20),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Demand map', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                      'TODO: live feeder positions + virtual stop map once '
                      'pooling-service / stop-optimization-service expose '
                      'read endpoints.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});

  final _StatTile stat;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              stat.value,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              stat.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
