import '../../features/booking/domain/booking_failure.dart';
import '../../features/booking/domain/booking_models.dart';
import '../../features/booking/domain/booking_state_machine.dart';

/// User-facing Bahasa Indonesia text for booking (Home + Trips).
class BookingStrings {
  BookingStrings._();

  // Home
  static const homeTitle = 'Siap berangkat?';
  static const homeSubtitle = 'Mau ke mana hari ini?';
  static const homeSearchHint = 'Mau ke mana?';
  static const bookFeeder = 'Pesan\nFeeder';
  static const routeInfo = 'Info\nRute';
  static const locate = 'Lokasi saya';
  static const plannerTitle = 'Rencanakan Perjalanan';
  static String feedersNearby(int count) => '$count FEEDER TERDEKAT';

  // Pooling
  static const poolingTitle = 'Pooling saat ini';
  static const poolingActive = 'AKTIF';
  static String poolingSummary(int count) => '$count titik virtual aktif di sekitarmu.';
  static const poolingSummaryGeneric = 'Titik virtual muncul mengikuti permintaan di sekitarmu.';
  static const poolingJoin = 'Gabung pool agar jemputan lebih cepat';
  static const origin = 'Asal';
  static const destination = 'Tujuan';
  static const currentLocation = 'Lokasi saat ini';
  static const originUnavailable = 'Lokasi saat ini belum tersedia.';
  static const retryOrigin = 'Coba lagi';
  static const originHint = 'Cari lokasi asal';
  static const destinationHint = 'Cari tujuan';
  static const swapEndpoints = 'Tukar asal dan tujuan';
  static const suggestedPlaces = 'Saran tempat';
  static const confirmDestination = 'Konfirmasi Tujuan';
  static const noDestinationMatch = 'Tujuan tidak ditemukan.';
  static const placeholderLocations = 'Data lokasi contoh (belum ada GPS & pencarian alamat)';
  static const findRoute = 'Cari rute';
  static const planningLoading = 'Mencari rute terbaik...';

  // Consent (UU PDP)
  static const consentTitle = 'Izin pemrosesan lokasi';
  static const consentBody =
      'Untuk merencanakan perjalanan, KONEKTA memproses lokasi asal dan tujuanmu. '
      'Lokasi hanya dipakai untuk menentukan titik jemput, rute, dan feeder, '
      'dan tidak dibagikan ke pihak lain.';
  static const consentAccept = 'Setuju dan lanjutkan';
  static String consentPolicy(String version) => 'Versi kebijakan $version';

  // Plan
  static const planTitle = 'Rute Rekomendasi';
  static const routeDetails = 'Detail';
  static const hideRouteDetails = 'Tutup';
  static String walkLeg(String duration, String distance) => 'Jalan kaki $duration ($distance)';
  static String rideLeg(String duration, String distance) => 'Naik feeder $duration ($distance)';
  static String feederArrivesIn(String duration) => 'Feeder terdekat tiba dalam $duration';
  static const walk = 'Jalan kaki';
  static String feederLine(String? corridorId) => corridorId == null ? feeder : '$feeder $corridorId';
  static String pickupAt(String stopName) => 'Jemput di $stopName';
  static String timeRange(DateTime start, DateTime end) => '${time(start)} – ${time(end)}';
  static const fare = 'Perkiraan tarif';
  static const pickupStop = 'Titik jemput';
  static const dropoffStop = 'Titik turun';
  static const confirmBooking = 'Pesan sekarang';
  static const planExpiredHint = 'Rencana ini sudah kedaluwarsa. Cari rute lagi.';
  static String planValidUntil(String time) => 'Berlaku sampai $time';

  // Stops
  static const stopStatic = 'Halte';
  static const stopVirtual = 'Titik virtual';
  static const stopMoved = 'Titik jemput dipindahkan. Lihat peta untuk lokasi terbaru.';
  static String stopValidUntil(String time) => 'Titik ini berlaku sampai $time';

  // Active booking
  static const activeTripTitle = 'Perjalanan aktif';
  static const boarded = 'Saya sudah naik';
  static const cancel = 'Batalkan';
  static const dismiss = 'Tutup';
  static const bookAgain = 'Pesan lagi';
  static const feeder = 'Feeder';
  static const etaToPickup = 'Tiba di titik jemput';
  static const seeMap = 'Pantau posisi feeder di tab Peta.';
  static const cancelDialogTitle = 'Batalkan perjalanan?';
  static const cancelDialogKeep = 'Tidak';
  static const cancelDialogConfirm = 'Ya, batalkan';
  static String cancelDialogBody(int feeIdr) => feeIdr > 0
      ? 'Kamu akan dikenai biaya pembatalan ${rupiah(feeIdr)}.'
      : 'Pembatalan saat ini tidak dikenai biaya.';

  static String statusLabel(BookingStatus status) => switch (status) {
        BookingStatus.requested => 'Memproses pesanan',
        BookingStatus.matching => 'Mencari feeder',
        BookingStatus.confirmed => 'Feeder ditemukan',
        BookingStatus.feederArriving => 'Feeder segera tiba',
        BookingStatus.boarded => 'Dalam perjalanan',
        BookingStatus.completed => 'Selesai',
        BookingStatus.cancelled => 'Dibatalkan',
        BookingStatus.failed => 'Feeder tidak tersedia',
        BookingStatus.noShow => 'Terlewat',
        BookingStatus.expired => 'Kedaluwarsa',
      };

  static String statusDescription(BookingStatus status) => switch (status) {
        BookingStatus.requested => 'Pesananmu sedang diproses.',
        BookingStatus.matching => 'Kami sedang mencarikan feeder untukmu. Mohon tunggu sebentar.',
        BookingStatus.confirmed => 'Silakan berjalan ke titik jemput.',
        BookingStatus.feederArriving => 'Feeder sudah dekat titik jemput. Tekan "Saya sudah naik" setelah naik.',
        BookingStatus.boarded => 'Selamat jalan! Perjalanan selesai saat feeder tiba di titik turun.',
        BookingStatus.completed => 'Kamu sudah sampai. Terima kasih telah menggunakan KONEKTA.',
        BookingStatus.cancelled => 'Perjalanan ini telah dibatalkan.',
        BookingStatus.failed => 'Belum ada feeder yang bisa melayani rute ini. Coba lagi beberapa saat lagi.',
        BookingStatus.noShow => 'Feeder sudah berangkat dari titik jemput sebelum kamu naik.',
        BookingStatus.expired => 'Pesanan kedaluwarsa karena tidak segera diproses.',
      };

  // Connectivity
  static const offline = 'Koneksi terputus. Menyambungkan ulang...';
  static const syncing = 'Memperbarui status...';
  static const retry = 'Coba lagi';

  // Trips
  static const tripsTitle = 'Perjalanan';
  static const historyTitle = 'Riwayat';
  static const historyEmpty = 'Belum ada riwayat perjalanan.';
  static const loadMore = 'Muat lebih banyak';
  static const noActiveTrip = 'Tidak ada perjalanan aktif.';

  static String failure(BookingFailureCode code) => switch (code) {
        BookingFailureCode.invalidTransition => 'Status perjalanan sudah berubah. Data diperbarui.',
        BookingFailureCode.activeBookingExists => 'Kamu masih punya perjalanan aktif.',
        BookingFailureCode.idempotencyKeyReused ||
        BookingFailureCode.idempotencyKeyRequired =>
          'Pesanan tidak dapat diproses. Coba cari rute lagi.',
        BookingFailureCode.planExpired => 'Rencana perjalanan sudah kedaluwarsa. Cari rute lagi.',
        BookingFailureCode.notFound => 'Perjalanan tidak ditemukan.',
        BookingFailureCode.consentRequired => 'Berikan izin pemrosesan lokasi untuk melanjutkan.',
        BookingFailureCode.noRoute => 'Belum ada rute feeder untuk kedua titik ini, atau jaraknya terlalu dekat.',
        BookingFailureCode.outsideServiceArea => 'Asal dan tujuan harus berada di area layanan Bandung.',
        BookingFailureCode.routingUnavailable => 'Layanan rute sedang tidak tersedia. Coba lagi.',
        BookingFailureCode.concurrentUpdate => 'Perjalanan sedang diperbarui. Coba lagi.',
        BookingFailureCode.invalidCursor => 'Gagal memuat riwayat. Coba lagi.',
        BookingFailureCode.unauthorized => 'Sesi berakhir. Silakan masuk kembali.',
        BookingFailureCode.offline => 'Tidak ada koneksi internet.',
        BookingFailureCode.timeout => 'Server terlalu lama merespons. Coba lagi.',
        BookingFailureCode.invalidRequest => 'Permintaan tidak valid.',
        BookingFailureCode.server || BookingFailureCode.unknown => 'Terjadi kesalahan. Coba lagi.',
      };

  static String stopType(StopType type) => switch (type) {
        StopType.staticStop => stopStatic,
        StopType.virtualStop => stopVirtual,
      };

  // Formatting
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

  /// `Rp5.000`
  static String rupiah(int amountIdr) {
    final digits = amountIdr.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '${amountIdr < 0 ? '-' : ''}Rp$buffer';
  }

  static String minutes(int value) => '$value menit';

  /// Seconds rounded up to whole minutes; under a minute reads "< 1 menit".
  static String durationFromSeconds(num seconds) {
    if (seconds < 60) return '< 1 menit';
    return minutes((seconds / 60).ceil());
  }

  static String distance(double meters) =>
      meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

  /// `08.15` in local time.
  static String time(DateTime value) {
    final local = value.toLocal();
    return '${_two(local.hour)}.${_two(local.minute)}';
  }

  /// `16 Okt 2026, 08.15` in local time.
  static String dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day} ${_months[local.month - 1]} ${local.year}, ${time(local)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
