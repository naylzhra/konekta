import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/core/navigation/nav_instructions.dart';
import 'package:latlong2/latlong.dart';

NavStep _step(String type, {String? modifier, String name = '', required LatLng at}) =>
    NavStep(type: type, modifier: modifier, name: name, distanceM: 100, location: at);

void main() {
  const here = LatLng(-6.9070, 107.6106);
  final depart = _step('depart', name: 'Jalan Merdeka', at: here);
  final turn = _step('turn', modifier: 'left', name: 'Jalan Aceh', at: const LatLng(-6.9097, 107.6106));
  final arrive = _step('arrive', at: const LatLng(-6.9098, 107.6124));

  test('upcoming step skips departure and maneuvers already reached', () {
    expect(upcomingStep([depart, turn, arrive], here), turn);
    expect(upcomingStep([depart, turn, arrive], const LatLng(-6.90971, 107.61061)), arrive);
    expect(upcomingStep([depart], here), isNull);
  });

  test('instructions are worded in Indonesian', () {
    expect(instructionFor(turn), 'Belok kiri ke Jalan Aceh');
    expect(instructionFor(_step('turn', modifier: 'uturn', at: here)), 'Putar balik');
    expect(instructionFor(_step('new name', name: 'Jalan Sumatra', at: here)), 'Lanjut lurus di Jalan Sumatra');
    expect(instructionFor(arrive), 'Tiba di tujuan');
    expect(instructionFor(arrive, arrivalName: 'Halte A'), 'Tiba di Halte A');
  });

  test('distances and ETA are formatted for a glance', () {
    expect(formatDistance(43), '40 m');
    expect(formatDistance(260), '250 m');
    expect(formatDistance(1530), '1,5 km');
    expect(formatEta(61), '2 mnt');
    expect(formatEta(3900), '1 j 5 mnt');
  });
}
