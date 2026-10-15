import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/strings/live_tracking_strings.dart';
import '../domain/service_area.dart';


/// TODO: the public OSM tile server is for development only (its usage policy forbids heavy/production use)
class ServiceAreaMap extends StatelessWidget {
  const ServiceAreaMap({super.key, this.controller, this.initialCenter, this.markers = const [], this.onMapReady});

  final MapController? controller;

  /// [controller] must not move the camera before this fires.
  final VoidCallback? onMapReady;
  final LatLng? initialCenter;
  final List<Marker> markers;

  static const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static final _bounds = LatLngBounds(
    const LatLng(ServiceArea.minLat, ServiceArea.minLng),
    const LatLng(ServiceArea.maxLat, ServiceArea.maxLng),
  );

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter ?? ServiceArea.center,
        initialZoom: 15,
        minZoom: 11,
        maxZoom: 18,
        cameraConstraint: CameraConstraint.contain(bounds: _bounds),
        onMapReady: onMapReady,
      ),
      children: [
        TileLayer(urlTemplate: _tileUrl, userAgentPackageName: 'com.example.konekta_mobile'),
        MarkerLayer(markers: markers),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution(LiveTrackingStrings.osmAttribution)],
        ),
      ],
    );
  }
}
