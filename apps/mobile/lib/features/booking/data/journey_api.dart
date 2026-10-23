import '../../../core/api/api_client.dart';
import '../domain/booking_models.dart';
import '../domain/journey_models.dart';

class JourneyApi {
  const JourneyApi(this.api, this.token);

  final ApiClient api;
  final String token;

  Future<Journey> load(String bookingId, GeoPoint? location) async {
    final response = await api.send(
      'GET', '/bookings/${Uri.encodeComponent(bookingId)}/journey',
      token: token,
      query: {
        if (location != null) 'lat': '${location.lat}',
        if (location != null) 'lng': '${location.lng}',
      },
    );
    if (!response.isSuccess) throw StateError('Journey unavailable (${response.statusCode})');
    return Journey.fromJson(response.body as Map<String, dynamic>);
  }
}
