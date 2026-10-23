class DriverStrings {
  DriverStrings._();

  static const tabDuty = 'Dinas';
  static const tasksTitle = 'Halte yang perlu dilayani';
  static const tasksEmpty = 'Belum ada penumpang. Halte jemput dan turun muncul di sini saat ada pemesanan.';
  static const tasksFailed = 'Daftar halte belum dapat dimuat.';
  static const routeOrder = 'Lihat urutan halte rute';
  static const pickup = 'Jemput';
  static const dropoff = 'Turunkan';
  static const virtualStop = 'Halte virtual';
  static const staticStop = 'Halte tetap';
  static String seats(int n) => '$n penumpang';
  static const nextStop = 'Halte berikutnya';
  static String nextStopNumbered(int position) => 'Halte berikutnya · No. $position';
  static const afterThat = 'Selanjutnya';
  static const otherTaskStops = 'Halte lain dengan penumpang';
  static String passengersAt(int pickup, int dropoff) => [
        if (pickup > 0) '$pickup naik',
        if (dropoff > 0) '$dropoff turun',
      ].join(' · ');
  static const navigateHere = 'Arahkan ke sini';
  static const routing = 'Mencari rute...';
  static const routeUnavailable = 'Rute belum tersedia. Ikuti rute koridor.';
  static const arrived = 'Saya tiba';
  static const departed = 'Saya berangkat';
  static const arrivedNear = 'Anda sudah dekat halte. Tekan "Saya tiba" saat berhenti.';
  static const arrivedLogged = 'Kedatangan dicatat';
  static const departedLogged = 'Keberangkatan dicatat';
  static const eventFailed = 'Status halte belum tersimpan. Coba lagi.';
  static const departTitle = 'Berangkat dari halte?';
  static const departBody = 'Penumpang yang belum naik akan tercatat tidak hadir.';
  static const cancel = 'Batal';
  static const recenter = 'Kembali ke posisi saya';
  static const pickDirectionTitle = 'Pilih arah perjalanan';
  static const from = 'Dari';
  static const to = 'Ke';
  static const swapDirection = 'Tukar arah';
  static const startWithDirection = 'Mulai Bertugas';
  static String heading(String from, String to) => '$from → $to';
  static const switchDirection = 'Putar arah';
  static const switchDirectionTitle = 'Putar arah?';
  static String switchDirectionBody(String to) =>
      'Navigasi berikutnya mengikuti rute balik menuju $to. Penumpang baru dicocokkan dengan arah ini.';
}
