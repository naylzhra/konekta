import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/konekta_theme.dart';
import '../data/feeder_api.dart';
import '../domain/feeder_models.dart';

class RouteStopsPage extends StatefulWidget {
  const RouteStopsPage({super.key, required this.corridorId});

  final String corridorId;

  @override
  State<RouteStopsPage> createState() => _RouteStopsPageState();
}

class _RouteStopsPageState extends State<RouteStopsPage> {
  late final _api = FeederApi(ApiClient());
  late Future<CorridorRoute> _route = _api.routeStops(widget.corridorId);

  void _reload() => setState(() => _route = _api.routeStops(widget.corridorId));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Daftar halte rute')),
        body: FutureBuilder<CorridorRoute>(
          future: _route,
          builder: (context, snapshot) {
            if (!snapshot.hasData && !snapshot.hasError) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Daftar halte belum dapat dimuat.'),
                  TextButton(
                      onPressed: _reload, child: const Text('Coba lagi')),
                ]),
              );
            }
            final route = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.containerMargin),
              children: [
                Text(route.name, style: AppTextStyles.headlineLgMobile),
                if (route.isDummy)
                  const Text('Data rute sementara (dummy)', style: AppTextStyles.bodySm),
                const SizedBox(height: AppSpacing.xs),
                Text('${route.stops.length} halte sesuai urutan perjalanan',
                    style: AppTextStyles.bodySm),
                const SizedBox(height: AppSpacing.lg),
                for (final stop in route.stops)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 17,
                        backgroundColor: AppColors.primaryContainer,
                        child: Text('${stop.position}',
                            style: AppTextStyles.labelMd
                                .copyWith(color: AppColors.onPrimaryContainer)),
                      ),
                      title: Text(stop.name, style: AppTextStyles.bodyMd),
                      subtitle: stop.lat != null && stop.lng != null
                          ? Text('${stop.lat}, ${stop.lng}',
                              style: AppTextStyles.bodySm)
                          : null,
                    ),
                  ),
              ],
            );
          },
        ),
      );
}
