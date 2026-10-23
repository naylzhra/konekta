# Usulan titik jemput virtual dan navigasi

Permintaan perjalanan diproses di gateway tanpa memperlihatkan proses pooling
kepada penumpang. Setiap menit, gateway memeriksa trip plan dalam jendela
terakhir. Permintaan dalam koridor, arah, dan slot waktu yang sama dikelompokkan
berdasarkan lokasi jemput. Cluster yang memenuhi ambang dievaluasi dan muncul
sebagai `proposed` pada dashboard pemerintah. Titik virtual hanya dapat dipakai
untuk booking setelah petugas menyetujuinya. Selama belum disetujui, penumpang
diarahkan ke halte aktif terdekat pada koridor itu.

## Ambang yang dapat diubah

Semua variabel berikut dibaca gateway saat proses dimulai. Ubah nilainya pada
`infra/docker/docker-compose.yml` atau environment gateway, lalu jalankan ulang
gateway. Perubahan tidak mengubah hasil run yang sudah tersimpan.

| Variabel | Default | Fungsi |
| --- | ---: | --- |
| `VIRTUAL_STOP_AUTO_RUN` | `1` | `1` mengaktifkan pemindaian otomatis; `0` mematikannya. |
| `VIRTUAL_STOP_SCAN_INTERVAL_S` | `60` | Jarak antar pemindaian demand, dalam detik. |
| `VIRTUAL_STOP_WINDOW_DAYS` | `7` | Jendela waktu permintaan yang dianalisis, dalam hari. |
| `VIRTUAL_STOP_REQUEST_THRESHOLD` | `10` | Minimum jumlah **request trip plan** dalam satu cluster. Pencarian berulang dihitung sebagai request baru. |
| `VIRTUAL_STOP_CLUSTER_RADIUS_M` | `150` | Jarak tetangga DBSCAN antar lokasi jemput, dalam meter. |
| `VIRTUAL_STOP_SLOT_MINUTES` | `1440` | Ukuran slot waktu WIB. Default menggabungkan permintaan pada jam berapa pun dalam satu minggu; nilai harus membagi 1440. |
| `VIRTUAL_STOP_STOP_SPACING_M` | `300` | Batas minimum celah antara dua halte berurutan agar segmen boleh diisi usulan halte virtual, dalam meter. Celah harus **lebih dari** nilai ini. |

Ambang pendukung yang sudah ada pada pipeline, dan bisa diubah per pemanggilan
`POST /virtual-stops/runs` melalui `pooling_params`/`evaluation_params`:

| Parameter | Default run manual | Fungsi |
| --- | ---: | --- |
| `eps_m` | `150` m | Radius DBSCAN. Run otomatis memakai `VIRTUAL_STOP_CLUSTER_RADIUS_M`. |
| `min_pts` | `4` | Minimum request untuk membentuk cluster. Run otomatis memakai `VIRTUAL_STOP_REQUEST_THRESHOLD`. |
| `min_unique_users` | `5` | Minimum customer unik. Run otomatis memakai `1` karena ambang dihitung per request. |
| `min_active_days` | `3` | Minimum hari aktif. Run otomatis memakai `1`. |
| `min_temporal_consistency` | `0.3` | Minimum proporsi hari aktif. Run otomatis memakai `0`. |
| `max_radius_p80_m` | `250` m | Batas penyebaran 80% lokasi permintaan dalam cluster. |
| `min_corridor_progress_m` | `300` m | Minimum kemajuan perjalanan sepanjang koridor. |
| `corridor_buffer_m` | `100` m | Jarak maksimum titik usulan dari lintasan koridor. |
| `max_walk_m` | `400` m | Jarak jalan kaki maksimum yang dipakai evaluasi akses. |
| `min_walk_coverage` | `0.8` | Porsi berbobot permintaan yang harus terjangkau. |
| `min_stop_spacing_m` | `300` m | Batas celah halte berurutan untuk run otomatis. Segmen hanya memenuhi syarat bila panjangnya **lebih dari** nilai ini. |
| `max_shift_m` | `500` m | Radius di mana kandidat dianggap relokasi halte. Run otomatis memakai `0` agar hanya mengusulkan titik baru. |
| `max_added_travel_s` | `120` s | Tambahan waktu perjalanan feeder maksimum. |

Untuk run otomatis, titik usulan harus berada **di antara dua halte berurutan**
pada koridor. Panjang segmen di antara kedua halte itu harus lebih dari
`VIRTUAL_STOP_STOP_SPACING_M`; titik usulan boleh berada kurang dari 300 m dari
halte existing, termasuk halte virtual yang sudah disetujui. Setelah halte
disetujui, kedua segmen hasil pemecahan dievaluasi lagi secara terpisah. Jadi,
usulan baru di antara halte A dan halte virtual B hanya bisa muncul pada segmen
A–B jika panjang segmen itu sendiri lebih dari ambang.

Beberapa ambang lain seperti `catchment_m` berasal dari baris `corridors`, dan
`MAX_WALK_TO_STOP_M=800` berada di `services/gateway/app/bookings/config.py`.

## Routing menurut moda

`infra/osrm/prepare.ps1` menghasilkan graf terpisah dari PBF Bandung yang sama:
mobil (`car.lua`), pejalan kaki (`foot.lua`), dan motor
(`infra/osrm/motorcycle.lua`). Overlay `docker-compose.osrm.yml` menjalankan
masing-masing graf di port 5002, 5003, dan 5004. Profil pada URL OSRM saja
tidak mengganti moda; setiap moda harus menggunakan server dengan graf yang
sesuai. Feeder saat ini memakai graf mobil; tahapan jalan kaki memakai graf
pejalan kaki. Saat model perjalanan menambah tahap motor, gunakan graf motor.

Endpoint `GET /bookings/{id}/journey` mengembalikan garis rute, jarak, dan ETA
untuk jalan ke titik jemput, naik feeder, lalu jalan ke tujuan. Query `lat`
dan `lng` opsional dipakai untuk menghitung ulang sisa tahap aktif dari posisi
penumpang. Endpoint hanya dapat membaca booking milik akun yang login.

## Uji flow lokal

1. Siapkan graf dari `bandung.osm.pbf` dengan `infra/osrm/prepare.ps1`, lalu
   jalankan compose dasar dan overlay `docker-compose.osrm.yml` dengan `up -d --build`.
2. Jalankan dashboard (`cd apps/dashboard; npm run dev`) dan login sebagai
   akun `government` yang dibuat dengan `python -m app.cli.create_user` di
   kontainer gateway. Lihat `apps/dashboard/README.md` untuk perintah lengkap.
3. Di aplikasi penumpang, pilih titik asal berdekatan pada celah halte K1
   nomor 38–39 (sekitar `-6.90726, 107.61188`) dan tujuan yang lebih jauh
   searah rute, misalnya dekat halte 50. Lakukan 10 pencarian rute; tiap
   pencarian membuat satu trip plan. Ambang otomatis menghitung request,
   sehingga satu akun pun dapat menguji alur ini. Dalam penggunaan biasa,
   request dapat berasal dari banyak customer.
4. Tunggu paling lama `VIRTUAL_STOP_SCAN_INTERVAL_S` ditambah interval muat
   ulang dashboard 30 detik. Kandidat yang lolos evaluasi muncul sebagai
   `proposed` dengan jumlah request. Setujui dari dashboard.
5. Buat pencarian rute baru dari lokasi dekat titik yang disetujui. Booking
   akan memilih titik virtual aktif bila titik itu yang terdekat. Buka tab
   Peta: banner menampilkan tahap aktif dan sisa jarak, garis peta mengikuti
   rute tahap itu, dan panel bawah menunjukkan semua tahap perjalanan.

Jika kandidat belum disetujui atau evaluasi jaraknya gagal, booking tetap
memakai halte aktif terdekat. `BOOKING_SIMULATOR=1` dapat dipakai untuk demo
perubahan status perjalanan tanpa driver fisik; untuk alur driver sesungguhnya,
jalankan driver app dan kirim posisi feeder dari device driver.
