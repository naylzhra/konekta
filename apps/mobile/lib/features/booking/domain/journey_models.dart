import 'booking_models.dart';

class JourneyStage {
  const JourneyStage({
    required this.mode,
    required this.status,
    required this.destinationName,
    required this.destination,
    required this.distanceM,
    required this.durationS,
    required this.points,
  });

  factory JourneyStage.fromJson(Map<String, dynamic> json) => JourneyStage(
        mode: json['mode'] as String,
        status: json['status'] as String,
        destinationName: json['destination_name'] as String,
        destination: GeoPoint.fromJson(json['destination'] as Map<String, dynamic>),
        distanceM: (json['distance_m'] as num).toDouble(),
        durationS: (json['duration_s'] as num).toDouble(),
        points: [
          for (final point in json['points'] as List<dynamic>)
            GeoPoint.fromJson(point as Map<String, dynamic>),
        ],
      );

  final String mode;
  final String status;
  final String destinationName;
  final GeoPoint destination;
  final double distanceM;
  final double durationS;
  final List<GeoPoint> points;
}

class Journey {
  const Journey({required this.bookingId, required this.activeStage, required this.stages});

  factory Journey.fromJson(Map<String, dynamic> json) => Journey(
        bookingId: json['booking_id'] as String,
        activeStage: json['active_stage'] as int,
        stages: [
          for (final stage in json['stages'] as List<dynamic>)
            JourneyStage.fromJson(stage as Map<String, dynamic>),
        ],
      );

  final String bookingId;
  final int activeStage;
  final List<JourneyStage> stages;

  JourneyStage get current => stages[activeStage];
}
