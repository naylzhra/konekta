class LiveTrackingStrings {
  LiveTrackingStrings._();

  // Driver home
  static const driverTitle = 'Pengemudi';
  static String feederLabel(int number, String corridorName) => 'Feeder $number · $corridorName';
  static const startDuty = 'Mulai Bertugas';
  static const stopDuty = 'Selesai Bertugas';
  static const starting = 'Menyiapkan lokasi...';
  static const onDuty = 'Sedang bertugas — lokasi dibagikan';
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
}
