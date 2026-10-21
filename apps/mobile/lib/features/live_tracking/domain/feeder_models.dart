library;

class FeederOption {
  const FeederOption({required this.id, required this.number, required this.capacity, required this.available});

  factory FeederOption.fromJson(Map<String, dynamic> json) => FeederOption(
        id: json['id'] as String,
        number: json['number'] as int,
        capacity: json['capacity'] as int,
        available: json['available'] as bool,
      );

  final String id;
  final int number;
  final int capacity;

  /// False once another driver registered with this feeder.
  final bool available;
}

class CorridorOption {
  const CorridorOption({required this.id, required this.name, required this.feeders});

  factory CorridorOption.fromJson(Map<String, dynamic> json) => CorridorOption(
        id: json['id'] as String,
        name: json['name'] as String,
        feeders: [
          for (final feeder in json['feeders'] as List<dynamic>) FeederOption.fromJson(feeder as Map<String, dynamic>),
        ],
      );

  final String id;
  final String name;
  final List<FeederOption> feeders;

  List<FeederOption> get availableFeeders => feeders.where((f) => f.available).toList();
}

class AssignedFeeder {
  const AssignedFeeder({
    required this.id,
    required this.number,
    required this.capacity,
    required this.corridorId,
    required this.corridorName,
  });

  factory AssignedFeeder.fromJson(Map<String, dynamic> json) => AssignedFeeder(
        id: json['id'] as String,
        number: json['number'] as int,
        capacity: json['capacity'] as int,
        corridorId: json['corridor_id'] as String,
        corridorName: json['corridor_name'] as String,
      );

  final String id;
  final int number;
  final int capacity;
  final String corridorId;
  final String corridorName;
}

class FeederPosition {
  const FeederPosition({
    required this.feederId,
    required this.lat,
    required this.lng,
    this.heading,
    required this.occupancy,
    this.capacity,
    this.corridorId,
    required this.updatedAt,
  });

  factory FeederPosition.fromJson(Map<String, dynamic> json) => FeederPosition(
        feederId: json['feeder_id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        heading: (json['heading'] as num?)?.toDouble(),
        occupancy: json['occupancy'] as int,
        capacity: json['capacity'] as int?,
        corridorId: json['corridor_id'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String feederId;
  final double lat;
  final double lng;
  final double? heading;
  final int occupancy;

  /// Null from gateways older than the corridor feed.
  final int? capacity;
  final String? corridorId;
  final DateTime updatedAt;

  bool get isFull => capacity != null && occupancy >= capacity!;
}
