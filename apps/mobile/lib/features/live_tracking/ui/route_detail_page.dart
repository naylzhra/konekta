import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/strings/booking_strings.dart';
import '../../../core/strings/live_tracking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../domain/feeder_models.dart';

/// One route (corridor): service info, then its stops in travel order per
/// direction. A stop with a feeder due within a few minutes expands to show
/// it. Pops `true` when the passenger taps "Ikuti" to watch it on the map.
class RouteDetailPage extends StatefulWidget {
  const RouteDetailPage({
    super.key,
    required this.corridor,
    required this.loadStops,
    required this.loadArrivals,
    this.feederNumber,
    this.following = false,
    this.refreshEvery = const Duration(seconds: 20),
  });

  final CorridorOption corridor;
  final Future<CorridorRoute> Function(RouteDirection direction) loadStops;
  final Future<List<StopArrivals>> Function(RouteDirection direction) loadArrivals;

  /// "Feeder N" label for a feeder id, when known.
  final int? Function(String feederId)? feederNumber;

  /// Already watched on the map.
  final bool following;
  final Duration refreshEvery;

  @override
  State<RouteDetailPage> createState() => _RouteDetailPageState();
}

class _RouteDetailPageState extends State<RouteDetailPage> {
  Map<RouteDirection, CorridorRoute>? _routes;
  bool _failed = false;
  RouteDirection _direction = RouteDirection.forward;

  /// Feeders due per stop position, for [_direction].
  Map<int, List<StopArrival>> _arrivals = const {};
  final Set<int> _expanded = {};
  int _arrivalsRequest = 0;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(widget.refreshEvery, (_) => _loadArrivals());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final forward = await widget.loadStops(RouteDirection.forward);
      CorridorRoute? backward;
      try {
        backward = await widget.loadStops(RouteDirection.backward);
      } on Object {
        backward = null; // a one-way route still shows its forward stops
      }
      if (!mounted) return;
      setState(() {
        _routes = {
          RouteDirection.forward: forward,
          if (backward != null && backward.stops.isNotEmpty) RouteDirection.backward: backward,
        };
      });
      await _loadArrivals();
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _loadArrivals() async {
    if (_routes == null) return;
    final request = ++_arrivalsRequest;
    final direction = _direction;
    try {
      final items = await widget.loadArrivals(direction);
      if (!mounted || request != _arrivalsRequest) return;
      setState(() => _arrivals = {for (final item in items) item.position: item.arrivals});
    } on Object {
      // Keep the last known arrivals; the next refresh retries.
    }
  }

  void _showDirection(RouteDirection direction) {
    if (direction == _direction) return;
    setState(() {
      _direction = direction;
      _arrivals = const {};
      _expanded.clear();
    });
    _loadArrivals();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          LiveTrackingStrings.routeDetailTitle,
          style: AppTextStyles.headlineMd.copyWith(fontWeight: FontWeight.w700, color: AppColors.inverseSurface),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final routes = _routes;
    if (_failed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(LiveTrackingStrings.routeDetailFailed, style: AppTextStyles.bodyMd),
          TextButton(onPressed: _load, child: const Text(LiveTrackingStrings.retry)),
        ]),
      );
    }
    if (routes == null) return const Center(child: CircularProgressIndicator());
    final route = routes[_direction] ?? routes[RouteDirection.forward]!;
    return RefreshIndicator(
      onRefresh: _loadArrivals,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: AppSpacing.lg + MediaQuery.paddingOf(context).bottom),
        children: [
          _Header(
            corridor: widget.corridor,
            name: route.name,
            following: widget.following,
            onFollow: () => Navigator.of(context).pop(true),
          ),
          if (routes.length > 1)
            _DirectionTabs(routes: routes, selected: _direction, onSelect: _showDirection),
          _InfoCards(route: routes[RouteDirection.forward]!),
          const Divider(height: AppSpacing.lg, color: AppColors.surfaceContainerHighest),
          for (var i = 0; i < route.stops.length; i++)
            _StopRow(
              stop: route.stops[i],
              first: i == 0,
              last: i == route.stops.length - 1,
              finalStop: route.stops.last.name,
              arrivals: _arrivals[route.stops[i].position] ?? const [],
              expanded: _expanded.contains(route.stops[i].position),
              feederNumber: widget.feederNumber,
              onToggle: () => setState(() {
                final position = route.stops[i].position;
                if (!_expanded.remove(position)) _expanded.add(position);
              }),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.corridor, required this.name, required this.following, required this.onFollow});

  final CorridorOption corridor;
  final String name;
  final bool following;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.containerMargin,
        AppSpacing.md,
        AppSpacing.containerMargin,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RouteBadge(id: corridor.id),
              const SizedBox(width: AppSpacing.xs),
              if (corridor.isDummy)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text('Dummy', style: AppTextStyles.labelMd.copyWith(color: AppColors.onPrimary)),
                ),
              const Spacer(),
              FilledButton(
                onPressed: following ? null : onFollow,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                ),
                child: Text(following ? LiveTrackingStrings.following : LiveTrackingStrings.follow),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            name,
            style: AppTextStyles.headlineLgMobile.copyWith(fontWeight: FontWeight.w700, color: AppColors.inverseSurface),
          ),
        ],
      ),
    );
  }
}

/// Round route badge with the corridor id, shared with the Peta route list.
class RouteBadge extends StatelessWidget {
  const RouteBadge({super.key, required this.id, this.size = 40});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
      child: Text(
        id,
        maxLines: 1,
        style: AppTextStyles.labelMd.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w700, letterSpacing: 0),
      ),
    );
  }
}

/// "First stop - last stop" per direction, underlined when selected.
class _DirectionTabs extends StatelessWidget {
  const _DirectionTabs({required this.routes, required this.selected, required this.onSelect});

  final Map<RouteDirection, CorridorRoute> routes;
  final RouteDirection selected;
  final ValueChanged<RouteDirection> onSelect;

  String _label(RouteDirection direction) {
    final stops = routes[direction]!.stops;
    if (stops.length < 2) {
      return direction == RouteDirection.forward
          ? LiveTrackingStrings.directionForward
          : LiveTrackingStrings.directionBackward;
    }
    return LiveTrackingStrings.directionLabel(stops.first.name, stops.last.name);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.containerMargin),
      child: Row(
        children: [
          for (final direction in routes.keys)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(direction),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: direction == selected ? AppColors.primary : AppColors.surfaceContainerHighest,
                        width: direction == selected ? 2 : 1,
                      ),
                    ),
                  ),
                  child: Text(
                    _label(direction),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySm.copyWith(
                      color: direction == selected ? AppColors.primary : AppColors.inverseSurface,
                      fontWeight: direction == selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Operating hours, days and fare; each card only once it's set on the server.
class _InfoCards extends StatelessWidget {
  const _InfoCards({required this.route});

  final CorridorRoute route;

  @override
  Widget build(BuildContext context) {
    final fare = route.fareFromIdr;
    final cards = [
      if (route.operatingHours != null) (LiveTrackingStrings.operatingHours, route.operatingHours!),
      if (route.operatingDays != null) (LiveTrackingStrings.operatingDays, route.operatingDays!),
      if (fare != null) (LiveTrackingStrings.fare, LiveTrackingStrings.fareFrom(BookingStrings.rupiah(fare))),
    ];
    if (cards.isEmpty) return const SizedBox(height: AppSpacing.sm);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.containerMargin, AppSpacing.md, AppSpacing.containerMargin, 0),
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  children: [
                    Text(cards[i].$1, textAlign: TextAlign.center, style: AppTextStyles.bodySm),
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      cards[i].$2,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600, color: AppColors.inverseSurface),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

const _railWidth = 32.0;

/// Center of a stop's dot, level with its name.
const _dotY = 24.0;

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.first,
    required this.last,
    required this.finalStop,
    required this.arrivals,
    required this.expanded,
    required this.feederNumber,
    required this.onToggle,
  });

  final CorridorRouteStop stop;
  final bool first;
  final bool last;
  final String finalStop;
  final List<StopArrival> arrivals;
  final bool expanded;
  final int? Function(String feederId)? feederNumber;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final due = arrivals.isNotEmpty;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: AppSpacing.containerMargin - AppSpacing.xs),
          SizedBox(
            width: _railWidth,
            child: CustomPaint(painter: _RailPainter(first: first, last: last, highlighted: due)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: due ? onToggle : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            stop.name,
                            style: AppTextStyles.bodyMd.copyWith(
                              color: AppColors.inverseSurface,
                              fontWeight: first || due ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (due)
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            color: AppColors.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ),
                ),
                if (due && expanded)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.containerMargin, bottom: AppSpacing.xs),
                    child: Column(
                      children: [
                        for (var i = 0; i < arrivals.length; i++)
                          _ArrivalCard(
                            arrival: arrivals[i],
                            number: feederNumber?.call(arrivals[i].feederId),
                            finalStop: finalStop,
                            soonest: i == 0,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrivalCard extends StatelessWidget {
  const _ArrivalCard({required this.arrival, required this.number, required this.finalStop, required this.soonest});

  final StopArrival arrival;
  final int? number;
  final String finalStop;
  final bool soonest;

  @override
  Widget build(BuildContext context) {
    final at = DateTime.now().add(Duration(seconds: arrival.etaS));
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: soonest ? AppColors.surfaceContainerHigh : AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.surfaceContainerHighest),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_bus, color: soonest ? AppColors.primary : AppColors.inverseSurface),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    LiveTrackingStrings.fleetFeederTitle(number, arrival.feederId),
                    style: AppTextStyles.labelMd.copyWith(color: AppColors.onErrorContainer, letterSpacing: 0),
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '${LiveTrackingStrings.finalDestination} ',
                      style: AppTextStyles.labelMd.copyWith(fontSize: 10, letterSpacing: 0.5),
                    ),
                    TextSpan(
                      text: finalStop,
                      style: AppTextStyles.bodySm.copyWith(color: AppColors.inverseSurface),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                LiveTrackingStrings.etaMinutes(arrival.etaS),
                style: AppTextStyles.bodyMd.copyWith(
                  fontWeight: FontWeight.w700,
                  color: soonest ? AppColors.primary : AppColors.inverseSurface,
                ),
              ),
              Text(
                '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                style: AppTextStyles.bodySm,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Vertical line through the stop list with a dot at each stop.
class _RailPainter extends CustomPainter {
  const _RailPainter({required this.first, required this.last, required this.highlighted});

  final bool first;
  final bool last;
  final bool highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final line = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2;
    canvas.drawLine(Offset(x, first ? _dotY : 0), Offset(x, last ? _dotY : size.height), line);
    canvas.drawCircle(
      Offset(x, _dotY),
      highlighted ? 6 : 4,
      Paint()..color = highlighted ? AppColors.primary : AppColors.outlineVariant,
    );
  }

  @override
  bool shouldRepaint(_RailPainter oldDelegate) =>
      oldDelegate.first != first || oldDelegate.last != last || oldDelegate.highlighted != highlighted;
}
