import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/strings/live_tracking_strings.dart';
import '../domain/service_area.dart';

/// Mapbox tiles: `--dart-define=MAPBOX_TOKEN=pk...` (optionally `MAPBOX_STYLE=<owner>/<style>`)
const _mapboxToken = String.fromEnvironment('MAPBOX_TOKEN');
const _mapboxStyle = String.fromEnvironment('MAPBOX_STYLE', defaultValue: 'mapbox/streets-v12');
const _useMapbox = _mapboxToken != '';

class ServiceAreaMap extends StatelessWidget {
  const ServiceAreaMap({
    super.key,
    this.controller,
    this.initialCenter,
    this.markers = const [],
    this.onMapReady,
    this.interactive = true,
    this.onTap,
  });

  final MapController? controller;

  /// [controller] must not move the camera before this fires.
  final VoidCallback? onMapReady;
  final LatLng? initialCenter;
  final List<Marker> markers;

  /// False for a static preview (no pan/zoom, so it doesn't fight scrolling).
  final bool interactive;

  /// Taps on the map itself, not on a marker.
  final VoidCallback? onTap;

  static const _tileUrl = _useMapbox
      ? 'https://api.mapbox.com/styles/v1/$_mapboxStyle/tiles/256/{z}/{x}/{y}@2x?access_token=$_mapboxToken'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
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
        onTap: onTap == null ? null : (_, __) => onTap!(),
        interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all : InteractiveFlag.none),
      ),
      children: [
        TileLayer(urlTemplate: _tileUrl, userAgentPackageName: 'com.example.konekta_mobile'),
        MarkerLayer(markers: markers),
        const RichAttributionWidget(
          attributions: [
            if (_useMapbox) TextSourceAttribution(LiveTrackingStrings.mapboxAttribution),
            TextSourceAttribution(LiveTrackingStrings.osmAttribution),
            if (_useMapbox) TextSourceAttribution(LiveTrackingStrings.improveThisMap),
          ],
        ),
      ],
    );
  }
}
