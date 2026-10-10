import 'package:flutter/foundation.dart';

import '../data/booking_repository.dart';
import '../domain/booking_failure.dart';
import '../domain/booking_models.dart';
import 'booking_controller.dart';

/// Trips history (`GET /bookings`, cursor-paginated, newest first). Follows
/// [live] so a booking that changes status shows up without a refetch.
class TripHistoryController extends ChangeNotifier {
  TripHistoryController({required BookingRepository repository, BookingController? live, this.pageSize = 20})
      : _repository = repository,
        _live = live {
    _live?.addListener(_onLiveChanged);
  }

  final BookingRepository _repository;
  final BookingController? _live;
  final int pageSize;

  List<Booking> _items = const [];
  String? _cursor;
  bool _loaded = false;
  bool _loading = false;
  bool _loadingMore = false;
  BookingException? _error;
  int _generation = 0;
  bool _disposed = false;

  List<Booking> get items => _items;
  bool get isLoaded => _loaded;
  bool get isLoading => _loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _cursor != null;
  BookingException? get error => _error;

  Future<void> refresh() async {
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _notify();
    try {
      final page = await _repository.listBookings(limit: pageSize);
      if (generation != _generation) return;
      _items = page.items;
      _cursor = page.nextCursor;
      _loaded = true;
    } on BookingException catch (e) {
      if (generation != _generation) return;
      _error = e;
    } finally {
      if (generation == _generation) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final cursor = _cursor;
    if (cursor == null || _loading || _loadingMore) return;
    final generation = _generation;
    _loadingMore = true;
    _error = null;
    _notify();
    try {
      final page = await _repository.listBookings(cursor: cursor, limit: pageSize);
      if (generation != _generation) return;
      final known = {for (final b in _items) b.id};
      _items = [..._items, ...page.items.where((b) => !known.contains(b.id))];
      _cursor = page.nextCursor;
    } on BookingException catch (e) {
      if (generation == _generation) _error = e;
    } finally {
      _loadingMore = false;
      _notify();
    }
  }

  void _onLiveChanged() {
    final booking = _live?.current;
    if (booking == null || !_loaded) return;
    final index = _items.indexWhere((b) => b.id == booking.id);
    if (index == -1) {
      _items = [booking, ..._items];
    } else if (booking.version > _items[index].version) {
      _items = [..._items]..[index] = booking;
    } else {
      return;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _live?.removeListener(_onLiveChanged);
    super.dispose();
  }
}
