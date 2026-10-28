class LiveTrackingStrings {
  LiveTrackingStrings._();

  // Driver home
  static const driverTitle = 'Pengemudi';
  static String feederLabel(int number, String corridorName) => 'Feeder $number · $corridorName';
  static const startDuty = 'Mulai Bertugas';
  static const stopDuty = 'Selesai Bertugas';
  static const starting = 'Menyiapkan lokasi...';
  static const onDuty = 'Sedang bertugas, lokasi dibagikan';
  static const offDuty = 'Tidak bertugas';
  static String lastSent(String time) => 'Terakhir terkirim $time';
  static const waitingFirstFix = 'Menunggu sinyal GPS...';
  static const noFeeder =
      'Akun ini belum terhubung ke feeder. Hubungi admin untuk menghubungkan akun Anda ke feeder.';
  static const loadFailed = 'Gagal memuat data feeder.';
  static const retry = 'Coba Lagi';

  // Issues
  static const permissionDenied = 'Izin lokasi diperlukan untuk mulai bertugas.';
  static const permissionDeniedForever =
      'Izin lokasi ditolak permanen. Aktifkan izin lokasi di Pengaturan aplikasi.';
  static const locationServiceDisabled = 'Layanan lokasi (GPS) mati. Nyalakan GPS lalu coba lagi.';
  static const outsideServiceArea = 'Anda berada di luar area layanan Bandung Raya. Lokasi tidak dikirim.';
  static const weakGps = 'Sinyal GPS lemah, menunggu lokasi yang lebih akurat...';
  static const sendFailed = 'Gagal mengirim lokasi, mencoba lagi...';
  static const sessionExpired = 'Sesi Anda berakhir. Silakan masuk kembali.';
  static const openSettings = 'Buka Pengaturan';

  // Permission rationale
  static const rationaleTitle = 'Bagikan lokasi Anda';
  static const rationaleBody =
      'Selama bertugas, KONEKTA membagikan lokasi kendaraan Anda kepada penumpang yang menunggu feeder ini '
      'dan kepada sistem penugasan. Lokasi hanya dikirim saat Anda bertugas dan berhenti saat Anda menekan '
      '"Selesai Bertugas".';
  static const rationaleContinue = 'Lanjutkan';
  static const rationaleCancel = 'Batal';

  // Foreground service notification
  static const notificationTitle = 'KONEKTA sedang bertugas';
  static const notificationText = 'Lokasi kendaraan dibagikan ke penumpang.';
  static const notificationChannel = 'Lokasi bertugas';

  // Registration feeder picker
  static const corridorLabel = 'Koridor';
  static const corridorHint = 'Pilih koridor';
  static const feederLabelField = 'Feeder';
  static const feederHint = 'Pilih feeder';
  static String feederOption(int number, int capacity) => 'Feeder $number (kapasitas $capacity)';
  static const noFeederAvailable = 'Semua feeder di koridor ini sudah dipakai.';
  static const corridorsLoadFailed = 'Gagal memuat daftar koridor.';
  static const chooseFeeder = 'Pilih koridor dan feeder Anda';

  // Map
  static const osmAttribution = 'OpenStreetMap contributors';
  static const mapboxAttribution = 'Mapbox';
  static const improveThisMap = 'Improve this map';

  // Passenger map
  static const noActiveTrip = 'Belum ada perjalanan aktif';
  static const noActiveTripHint = 'Alur rute tetap terlihat. Posisi feeder muncul saat kendaraan beroperasi.';
  static const searchingFeeder = 'Mencari feeder untuk perjalanan Anda...';
  static const waitingFeederPosition = 'Menunggu posisi feeder...';
  static String feederTitle(String feederId) => 'Feeder $feederId';
  static String toPickup(String distance) => '$distance dari halte jemput';
  static String pickupAt(String stopName) => 'Halte jemput: $stopName';
  static const onBoard = 'Anda sedang di dalam feeder';
  static String occupancy(int count) => '$count penumpang di dalam';
  static String updatedAt(String time) => 'Diperbarui $time';
  static const feederStale = 'Posisi feeder tidak diperbarui. Feeder mungkin sedang offline.';
  static String feederStaleSince(String time) => 'Posisi terakhir pukul $time';
  static const reconnecting = 'Koneksi terputus, menyambungkan ulang...';
  static const showMyLocation = 'Tampilkan lokasi saya';
  static const turnOnGps = 'Nyalakan GPS';
  static const recenterOnMe = 'Kembali ke posisi saya';
  static const recenter = 'Pusatkan peta';
  static String feedersOnDuty(int count) => '$count feeder sedang beroperasi';

  // Route search
  static const searchRouteHint = 'Cari rute atau koridor';
  static const allRoutes = 'Semua rute';
  static const noRouteFound = 'Rute tidak ditemukan';
  static String routeFeeders(int count) => count == 0 ? 'Tidak ada feeder beroperasi' : '$count feeder beroperasi';
  static const clearRoute = 'Hapus filter rute';

  // Route list (Peta bottom sheet)
  static const routesTitle = 'Rute';
  static const watchMultiple = 'Pantau beberapa';
  static const pickRoutesHint = 'Pilih rute yang ingin dipantau di peta.';
  static String watchRoutes(int count) => count == 0 ? 'Pilih rute' : 'Pantau $count rute';
  static String watchingRoutes(List<String> names) =>
      names.length == 1 ? 'Memantau ${names.single}' : 'Memantau ${names.length} rute';
  static const showAllRoutes = 'Tampilkan semua';

  // Route detail
  static const routeDetailTitle = 'Detail Rute';
  static const follow = 'Ikuti';
  static const following = 'Diikuti';
  static const operatingHours = 'Jam operasional';
  static const operatingDays = 'Hari operasional';
  static const fare = 'Tarif';
  static String fareFrom(String rupiah) => 'Mulai $rupiah';
  static const directionForward = 'Arah pergi';
  static const directionBackward = 'Arah balik';
  static String directionLabel(String from, String to) => '$from - $to';
  static const finalDestination = 'TUJUAN AKHIR';
  static String etaMinutes(int etaS) => etaS < 60 ? 'Tiba' : '${(etaS / 60).round()} min';
  static const routeDetailFailed = 'Detail rute belum dapat dimuat.';
  static const fleetLoadFailed = 'Gagal memuat feeder. Ketuk untuk coba lagi.';

  // Feeder info (tapped on the map)
  static String fleetFeederTitle(int? number, String feederId) =>
      number == null ? 'Feeder $feederId' : 'Feeder $number';
  static String seats(int occupancy, int capacity) => '$occupancy/$capacity kursi terisi';
  static const full = 'Penuh';
  static const bookFromHome = 'Pesan dari tab Home untuk naik feeder.';

  static const passengerRationaleTitle = 'Tampilkan lokasi Anda';
  static const passengerRationaleBody =
      'KONEKTA memakai lokasi Anda untuk menampilkan posisi Anda di peta, dekat halte dan feeder. '
      'Dari layar peta ini, lokasi Anda tidak dikirim ke server.';
}
