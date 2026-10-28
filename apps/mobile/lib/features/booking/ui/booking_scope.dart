import 'package:flutter/widgets.dart';

import '../booking_session.dart';
import '../data/trip_locations.dart';

/// Owns booking's per-login objects for the passenger shell: the
/// [BookingSession] (incl. the app's single WsClient, DESIGN.md §5.1) and
/// [BookingDependencies], shared by the Home and Trips tabs. Wrap the tab
/// scaffold once; tabs read it with [BookingScope.of].
class BookingScope extends StatefulWidget {
  const BookingScope({super.key, required this.token, required this.child, this.locations});

  final String token;
  final Widget child;

  /// Defaults to [TripLocations.fromEnvironment].
  final TripLocations? locations;

  static BookingScopeData of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_BookingInherited>();
    assert(scope != null, 'No BookingScope above this widget');
    return scope!.data;
  }

  @override
  State<BookingScope> createState() => _BookingScopeState();
}

class BookingScopeData {
  const BookingScopeData({required this.session, required this.dependencies, required this.locations});

  final BookingSession session;
  final BookingDependencies dependencies;
  final TripLocations locations;
}

class _BookingScopeState extends State<BookingScope> {
  late final BookingScopeData _data;

  @override
  void initState() {
    super.initState();
    final session = BookingSession.create(token: widget.token);
    final dependencies = BookingDependencies.create(session);
    _data = BookingScopeData(
      session: session,
      dependencies: dependencies,
      locations: widget.locations ?? TripLocations.fromEnvironment(apiClient: session.apiClient),
    );
    if (!dependencies.isMock) session.wsClient.connect();
    dependencies.booking.start();
  }

  @override
  void dispose() {
    _data.dependencies.dispose();
    _data.session.wsClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _BookingInherited(data: _data, child: widget.child);
}

class _BookingInherited extends InheritedWidget {
  const _BookingInherited({required this.data, required super.child});

  final BookingScopeData data;

  @override
  bool updateShouldNotify(_BookingInherited oldWidget) => !identical(data, oldWidget.data);
}
