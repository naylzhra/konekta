import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/websocket/ws_client.dart';
import '../data/feeder_position_stream.dart';
import '../domain/feeder_models.dart';
import 'passenger_map_controller.dart';

/// Every feeder currently on duty, for the passenger map: a `GET
/// /feeders/live` snapshot kept current by the `corridor:<id>` WS topics.
/// Corridors double as routes until real route geometry exists, so route
/// search filters by corridor.
class FeederFleetController extends ChangeNotifier {
  FeederFleetController({
    required Future<List<CorridorOption>> Function() loadCorridors,
    required Future<List<FeederPosition>> Function() loadLive,
    required FeederPositionStream positions,
    Stream<WsConnectionState>? connection,
    DateTime Function()? clock,
    Duration pruneInterval = const Duration(seconds: 5),
  })  : _loadCorridors = loadCorridors,
        _loadLive = loadLive,
        _positions = positions,
        _connection = connection,
        _clock = clock ?? DateTime.now,
        _pruneInterval = pruneInterval;

  final Future<List<CorridorOption>> Function() _loadCorridors;
  final Future<List<FeederPosition>> Function() _loadLive;
  final FeederPositionStream _positions;
  final Stream<WsConnectionState>? _connection;
  final DateTime Function() _clock;
  final Duration _pruneInterval;

  final List<StreamSubscription<FeederPosition>> _subscriptions = [];
  StreamSubscription<WsConnectionState>? _connectionSubscription;
  Timer? _pruneTimer;
  bool _disposed = false;

  List<CorridorOption> _corridors = const [];
  final Map<String, FeederPosition> _feeders = {};
  final Map<String, DateTime> _heardAt = {};
  bool _loadFailed = false;
  Set<String> _corridorFilters = const {};

  List<CorridorOption> get corridors => _corridors;
  bool get loadFailed => _loadFailed;

  /// Routes (corridors) the map is narrowed to; empty shows every route.
  Set<String> get corridorFilters => _corridorFilters;

  /// The route the map is narrowed to, when it's exactly one.
  String? get corridorFilter => _corridorFilters.length == 1 ? _corridorFilters.single : null;
  CorridorOption? get selectedCorridor => corridor(corridorFilter);

  /// On-duty feeders, narrowed to [corridorFilters] when set.
  List<FeederPosition> get feeders => [
        for (final feeder in _feeders.values)
          if (_corridorFilters.isEmpty || _corridorFilters.contains(corridorIdOf(feeder))) feeder,
      ];

  int get onDutyCount => _feeders.length;

  CorridorOption? corridor(String? id) {
    for (final corridor in _corridors) {
      if (corridor.id == id) return corridor;
    }
    return null;
  }

  /// From the position, else from the `/corridors` fleet list.
  String? corridorIdOf(FeederPosition feeder) {
    if (feeder.corridorId != null) return feeder.corridorId;
    for (final corridor in _corridors) {
      if (corridor.feeders.any((f) => f.id == feeder.feederId)) return corridor.id;
    }
    return null;
  }

  FeederOption? feederOption(String feederId) {
    for (final corridor in _corridors) {
      for (final feeder in corridor.feeders) {
        if (feeder.id == feederId) return feeder;
      }
    }
    return null;
  }

  /// Routes whose name or id contains [query] (case-insensitive).
  List<CorridorOption> searchRoutes(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _corridors;
    return [
      for (final corridor in _corridors)
        if (corridor.name.toLowerCase().contains(q) || corridor.id.toLowerCase().contains(q)) corridor,
    ];
  }

  int onDutyOn(String corridorId) => _feeders.values.where((f) => corridorIdOf(f) == corridorId).length;

  void filterByCorridor(String? corridorId) => filterByCorridors({if (corridorId != null) corridorId});

  void filterByCorridors(Iterable<String> corridorIds) {
    final next = Set<String>.unmodifiable(corridorIds.toSet());
    if (setEquals(next, _corridorFilters)) return;
    _corridorFilters = next;
    _notify();
  }

  Future<void> start() async {
    _pruneTimer = Timer.periodic(_pruneInterval, (_) => _prune());
    var wasConnected = true;
    _connectionSubscription = _connection?.listen((state) {
      final connected = state == WsConnectionState.connected;
      // Reports sent while we were offline were missed: re-read the snapshot.
      if (connected && !wasConnected) unawaited(_refreshSnapshot());
      wasConnected = connected;
    });
    await load();
  }

  /// (Re)loads corridors and the snapshot; also the retry after [loadFailed].
  Future<void> load() async {
    try {
      final corridors = await _loadCorridors();
      if (_disposed) return;
      _corridors = corridors;
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _subscriptions
        ..clear()
        ..addAll([for (final c in corridors) _positions.subscribeCorridor(c.id).listen(_onPosition)]);
      _loadFailed = false;
    } on Object {
      _loadFailed = true;
      _notify();
      return;
    }
    await _refreshSnapshot();
  }

  Future<void> _refreshSnapshot() async {
    try {
      final live = await _loadLive();
      if (_disposed) return;
      final now = _clock();
      _feeders
        ..clear()
        ..addEntries(live.map((p) => MapEntry(p.feederId, p)));
      _heardAt
        ..clear()
        ..addEntries(live.map((p) => MapEntry(p.feederId, now)));
      _loadFailed = false;
    } on Object {
      _loadFailed = true;
    }
    _notify();
  }

  void _onPosition(FeederPosition position) {
    final previous = _feeders[position.feederId];
    if (previous != null && !position.updatedAt.isAfter(previous.updatedAt)) return;
    _feeders[position.feederId] = position;
    _heardAt[position.feederId] = _clock();
    _notify();
  }

  /// Drops feeders not heard from for the gateway's position TTL: they went
  /// off duty or lost signal.
  void _prune() {
    final now = _clock();
    final expired = [
      for (final MapEntry(:key, :value) in _heardAt.entries)
        if (now.difference(value) >= PassengerMapController.staleAfter) key,
    ];
    if (expired.isEmpty) return;
    for (final id in expired) {
      _feeders.remove(id);
      _heardAt.remove(id);
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _connectionSubscription?.cancel();
    _pruneTimer?.cancel();
    super.dispose();
  }
}
