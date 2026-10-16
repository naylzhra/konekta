import 'package:latlong2/latlong.dart';

class ServiceArea {
  ServiceArea._();

  static const minLat = -7.05;
  static const maxLat = -6.80;
  static const minLng = 107.50;
  static const maxLng = 107.75;

  static const center = LatLng(-6.9218, 107.6070);

  static bool contains(double lat, double lng) => lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;
}
