import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// One OSRM maneuver from the gateway (`type`/`modifier` follow OSRM's
/// vocabulary); worded for display by [instructionFor].
class NavStep {
  const NavStep({
    required this.type,
    this.modifier,
    required this.name,
    required this.distanceM,
    required this.location,
  });

  factory NavStep.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>;
    return NavStep(
      type: json['type'] as String,
      modifier: json['modifier'] as String?,
      name: json['name'] as String? ?? '',
      distanceM: (json['distance_m'] as num).toDouble(),
      location: LatLng((location['lat'] as num).toDouble(),
          (location['lng'] as num).toDouble()),
    );
  }

  final String type;
  final String? modifier;
  final String name;
  final double distanceM;
  final LatLng location;
}

const _distance = Distance();

/// The maneuver the driver should prepare for next: the first step after
/// departure that is still ahead. The route is refetched from the live
/// position, so steps behind the driver drop off on their own.
NavStep? upcomingStep(List<NavStep> steps, LatLng here) {
  for (final step in steps) {
    if (step.type == 'depart') continue;
    // Within ~15 m we are at the maneuver; show the one after it.
    if (_distance(here, step.location) < 15 && step != steps.last) continue;
    return step;
  }
  return null;
}

double metresTo(LatLng here, LatLng there) => _distance(here, there);

String formatDistance(double metres) {
  if (metres < 1000) {
    final rounded = metres < 100 ? (metres / 10).round() * 10 : (metres / 50).round() * 50;
    return '$rounded m';
  }
  return '${(metres / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
}

String formatEta(double seconds) {
  final minutes = (seconds / 60).ceil();
  return minutes < 60 ? '$minutes mnt' : '${minutes ~/ 60} j ${minutes % 60} mnt';
}

/// [arrivalName] names the destination on the final step (OSRM only knows
/// the street).
String instructionFor(NavStep step, {String? arrivalName}) {
  final onto = step.name.isEmpty ? '' : ' ke ${step.name}';
  final along = step.name.isEmpty ? '' : ' di ${step.name}';
  switch (step.type) {
    case 'arrive':
      return arrivalName == null ? 'Tiba di tujuan' : 'Tiba di $arrivalName';
    case 'roundabout':
    case 'rotary':
    case 'roundabout turn':
      return 'Masuk bundaran$onto';
    case 'exit roundabout':
    case 'exit rotary':
      return 'Keluar bundaran$onto';
    case 'continue':
    case 'new name':
      return 'Lanjut lurus$along';
    case 'merge':
      return 'Bergabung$onto';
    case 'on ramp':
      return 'Masuk jalur$onto';
    case 'off ramp':
      return 'Keluar jalur$onto';
    case 'fork':
      return '${_side(step.modifier) == null ? 'Ambil cabang' : 'Ambil cabang ${_side(step.modifier)}'}$onto';
    case 'end of road':
      return '${_turnVerb(step.modifier)} di ujung jalan$onto';
  }
  if (step.modifier == 'straight') return 'Lurus$along';
  return '${_turnVerb(step.modifier)}$onto';
}

String? _side(String? modifier) => switch (modifier) {
      'left' || 'slight left' || 'sharp left' => 'kiri',
      'right' || 'slight right' || 'sharp right' => 'kanan',
      _ => null,
    };

String _turnVerb(String? modifier) => switch (modifier) {
      'left' => 'Belok kiri',
      'right' => 'Belok kanan',
      'slight left' => 'Serong kiri',
      'slight right' => 'Serong kanan',
      'sharp left' => 'Belok tajam ke kiri',
      'sharp right' => 'Belok tajam ke kanan',
      'uturn' => 'Putar balik',
      _ => 'Lanjut',
    };

IconData iconFor(NavStep step) {
  if (step.type == 'arrive') return Icons.place;
  if (step.type.contains('roundabout') || step.type.contains('rotary')) {
    return Icons.roundabout_left;
  }
  if (step.type == 'fork') {
    return _side(step.modifier) == 'kanan' ? Icons.fork_right : Icons.fork_left;
  }
  if (step.type == 'merge') return Icons.merge;
  return switch (step.modifier) {
    'left' => Icons.turn_left,
    'right' => Icons.turn_right,
    'slight left' => Icons.turn_slight_left,
    'slight right' => Icons.turn_slight_right,
    'sharp left' => Icons.turn_sharp_left,
    'sharp right' => Icons.turn_sharp_right,
    'uturn' => Icons.u_turn_left,
    _ => Icons.straight,
  };
}
