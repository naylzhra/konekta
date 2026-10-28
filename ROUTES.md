# Rute KONEKTA

## Feeder 1 — K1

K1 punya dua arah. Driver memilih arah saat mulai bertugas, dan penumpang hanya dicocokkan dengan feeder yang searah dengan perjalanannya. Kedua daftar di bawah menjadi sumber migrasi `009_feeder_1_route.sql` (pergi) dan `013_k1_return_route.sql` (balik), dibuat oleh `infra/db/generate_feeder_1_route.py`. Garis jalan kedua arah dibangun dengan `python -m app.cli.sync_k1_route`.

### Arah pergi (`forward`)

Simpang Soetta Kiaracondong 2 → Pasar Baru ABC. Urutan dan koordinat berikut diberikan langsung untuk implementasi rute feeder 1. Koordinat menggunakan format `latitude, longitude` (WGS84). Sesuai koreksi berikutnya, koordinat stop 40 dan 41 ditukar, sedangkan nama dan urutannya dipertahankan. Koordinat stop 39–42 dikoreksi ke posisi aslinya di peta OpenStreetMap: 39 dan 40 di titik simpang jalan masing-masing (Merdeka × L.L. RE. Martadinata/Riau, Sumatra × Aceh), 41 di tepi Taman Lalu Lintas Ade Irma Suryani, 42 di SMP Negeri 2 (Jalan Sumatra). Belokan kiri Jalan Merdeka → Jalan Aceh dilarang di data OSM, sehingga `sync_k1_route` menyambungnya secara manual. Daftar ini juga menjadi sumber untuk migrasi `009_feeder_1_route.sql`.

| Urutan | Stop | Latitude | Longitude |
| ---: | --- | ---: | ---: |
| 1 | Simpang Soetta Kiaracondong 2 | -6.945891140531955 | 107.64085963908062 |
| 2 | SPBU Simpang Buah Batu Soekarno Hatta | -6.947425172783311 | 107.63533488425557 |
| 3 | Seberang Jalan Guntursari Wetan | -6.946594391230343 | 107.6324962335247 |
| 4 | Seberang Jalan Kayuagung II | -6.945183740360205 | 107.63082509728422 |
| 5 | Institut Seni Budaya Indonesia Bandung (ISBI) | -6.9423298377358 | 107.62862716606274 |
| 6 | SMK Negeri 8 Bandung | -6.939958288975682 | 107.6287899954331 |
| 7 | Kantor PLN Jalan Karawitan | -6.938140485064181 | 107.628829877704 |
| 8 | Jalan Guntur Madu | -6.937378287927679 | 107.62708186050946 |
| 9 | Simpang Amarandana - Maskumambang | -6.935455685842529 | 107.62679465812376 |
| 10 | Dinas Pengendalian Penduduk dan Keluarga Berencana | -6.93340051039306 | 107.62825120985471 |
| 11 | Dinas Ketenaga Kerjaan Kota Bandung | -6.932705666601055 | 107.62705766506294 |
| 12 | Jalan Kangkung | -6.930707148786766 | 107.62643602636791 |
| 13 | Simpang Talaga Bodas - Terusan Galunggung | -6.928917634019321 | 107.6257612176466 |
| 14 | Seberang SD Al-Azhar 36 Bandung | -6.927221536371979 | 107.62393081024204 |
| 15 | Taman Pers Malabar I | -6.92569958428304 | 107.62377623352447 |
| 16 | Simpang Malabar - Gatot Subroto I | -6.923125679726461 | 107.62497081024206 |
| 17 | Simpang Samoja - Malabar | -6.920270232997806 | 107.62502008140613 |
| 18 | Kantor Pos Kosambi | -6.919066979107588 | 107.62405497955491 |
| 19 | Pasar Kosambi Jalan Baranang Siang | -6.920080883608585 | 107.62215060653965 |
| 20 | Katapang Kaler I | -6.921000233244171 | 107.62036914886797 |
| 21 | Simpang Naripan - Sunda I | -6.921455678898905 | 107.61803842003206 |
| 22 | Jalan Panaitan | -6.919250232653631 | 107.61834206421138 |
| 23 | Jalan Sunda | -6.917790082887422 | 107.61839623352441 |
| 24 | SPBU Jalan Sunda | -6.916185676288765 | 107.61875789489845 |
| 25 | Balai Bahasa Jawa Barat | -6.9136654307700685 | 107.61746081632977 |
| 26 | Taman Musik Jalan Sumbawa | -6.911522673980901 | 107.61667097955483 |
| 27 | Simpang Banda - Belitung | -6.911235022966366 | 107.61759206421141 |
| 28 | Simpang Bangka - Belitung | -6.911488277432325 | 107.61973570839082 |
| 29 | Simpang Menado - Aceh 2 | -6.909602187342959 | 107.62147349965112 |
| 30 | Polsek Bandung Wetan I | -6.908577626619054 | 107.62173811647244 |
| 31 | Pasar Cihapit I | -6.907525672003903 | 107.62340133537548 |
| 32 | Simpang Brantas - Cihapit 2 | -6.906555671524294 | 107.62471842003204 |
| 33 | Taman Cibeunying Selatan | -6.9053599749537575 | 107.62476123352427 |
| 34 | Simpang Cilaki - Cimanuk | -6.902810878177427 | 107.62200445442124 |
| 35 | Museum Pos Indonesia | -6.9017182734819436 | 107.62056081024176 |
| 36 | Taman Segitiga Trunojoyo I | -6.901792413748248 | 107.6158242507189 |
| 37 | Simpang Sultan Tirtayasa - Trunojoyo I | -6.902372414100083 | 107.61442060653962 |
| 38 | Jalan Sultan Agung | -6.904232187593347 | 107.61278113615916 |
| 39 | Simpang Merdeka - Riau | -6.90699 | 107.61061 |
| 40 | Simpang Sumatera - Aceh | -6.909767 | 107.612391 |
| 41 | Taman Lalu Lintas Kota Bandung | -6.9122313413532686 | 107.61442513113882 |
| 42 | SMP Negeri 2 Bandung | -6.913796517478549 | 107.61471115735989 |
| 43 | Polrestabes Bandung I | -6.9144882786465 | 107.61198040283742 |
| 44 | SD Negeri Merdeka | -6.914732730637008 | 107.61122996791904 |
| 45 | Museum Mandala Wangsit Siliwangi | -6.916952817024778 | 107.61164130924132 |
| 46 | Simpang Kejaksaan - Markoni | -6.918235026589139 | 107.6115900814061 |
| 47 | Jalan Braga Gang Cikapundung | -6.917700882859352 | 107.6099164372268 |
| 48 | Suniaraja Braga | -6.916006500796297 | 107.60826047293267 |
| 49 | Banceuy - Suniaraja | -6.915521539867314 | 107.60614623801028 |
| 50 | Pasar Baru | -6.917566485392181 | 107.60486950654098 |
| 51 | Pasar Baru ABC | -6.918301385527375 | 107.60567416923172 |

### Arah balik (`backward`)

Pasar Baru ABC → Simpang Soetta Kiaracondong 2. Urutan halte diberikan langsung. Koordinat stop 2, 3, 6, 8, dan 46 diberikan langsung; koordinat lain diambil dari node halte bus OpenStreetMap yang namanya sama (di OSM banyak halte rute ini sudah tercatat, misalnya "Seberang Jalan Melania RRI Bandung"), bukan dari Google Maps. Di data OSM sebagian Jalan Diponegoro di depan Lapangan Gasibu masih ditandai sedang dibangun (`highway=construction`), sehingga `sync_k1_route` menggambar ruas Taman Segitiga Trunojoyo 2 → Lapangan Gasibu A mengikuti Jalan Diponegoro secara manual. Koordinat Balai Kota Bandung berada di dalam area Balai Kota, jadi garis rute dilewatkan di Jalan Wastukencana tepat di sebelahnya (Wastukencana → Aceh → Merdeka, sesuai rute acuan `rute2.jpg`).

| Urutan | Stop | Latitude | Longitude | Sumber |
| ---: | --- | ---: | ---: | --- |
| 1 | Pasar Baru ABC | -6.9184052 | 107.6048509 | OSM: node halte |
| 2 | Simpang Banceuy - ABC | -6.918666178927174 | 107.60782597161595 | Diberikan |
| 3 | Jalan Braga Gang Cikapundung | -6.917615676996839 | 107.60962675865811 | Diberikan |
| 4 | Suniaraja Braga | -6.9161827 | 107.6079838 | OSM: node halte |
| 5 | Perintis Kemerdekaan | -6.9139566 | 107.6078989 | OSM: node halte |
| 6 | Balai Kota Bandung | -6.91284557798161 | 107.60953232373434 | Diberikan |
| 7 | Museum Kota Bandung | -6.9100874 | 107.609698 | OSM: node halte |
| 8 | Halte Santa Angela | -6.912630881264027 | 107.61087623352441 | Diberikan |
| 9 | Polrestabes Bandung 2 | -6.9145594 | 107.6116738 | OSM: node halte |
| 10 | Seberang SMP Negeri 2 Bandung | -6.9136201 | 107.6134632 | OSM: node halte |
| 11 | Paguyuban Pasundan | -6.9113208 | 107.6125214 | OSM: node halte |
| 12 | Dinas Arsip dan Perpustakaan Kota Bandung | -6.9084121 | 107.6134452 | OSM: node halte |
| 13 | Jalan Trunojoyo Riau Junction | -6.9063176 | 107.6126748 | OSM: node halte |
| 14 | Simpang Sultan Tirtayasa - Trunojoyo 2 | -6.9031524 | 107.613438 | OSM: node halte |
| 15 | Taman Segitiga Trunojoyo 2 | -6.9020021 | 107.6152506 | OSM: node halte |
| 16 | Lapangan Gasibu A | -6.901132 | 107.6199289 | OSM: node halte |
| 17 | Seberang Jalan Melania RRI Bandung | -6.9012477 | 107.6233825 | OSM: node halte |
| 18 | Seberang Museum Geologi | -6.9012818 | 107.6211108 | OSM: node halte |
| 19 | Simpang Cisangkuy - Cimanuk | -6.902942 | 107.6222778 | OSM: node halte |
| 20 | Simpang Cisangkuy - Citarum | -6.903513 | 107.623898 | OSM: node halte |
| 21 | Pet Park | -6.9048721 | 107.6264722 | OSM: node halte |
| 22 | Taman Cibeunying Utara | -6.9046471 | 107.6244523 | OSM: node halte |
| 23 | Simpang Brantas - Cihapit 2 | -6.9067733 | 107.6243252 | OSM: node halte |
| 24 | Pasar Cihapit 2 | -6.9078879 | 107.6229075 | OSM: node halte |
| 25 | Polsek Bandung Wetan 2 | -6.9083314 | 107.6215571 | OSM: node halte |
| 26 | Simpang Menado - Aceh 2 | -6.9098693 | 107.6210402 | OSM: node halte |
| 27 | Simpang Menado - Belitung | -6.91225 | 107.6201483 | OSM: node halte |
| 28 | Simpang Gudang Utara - Menado | -6.9152634 | 107.6193866 | OSM: node halte |
| 29 | Simpang Jawa - Sunda | -6.9157989 | 107.6174777 | OSM: node halte |
| 30 | Seberang SMP Negeri 5 Bandung | -6.9151846 | 107.6144795 | OSM: node halte |
| 31 | Simpang Sumatera - Natuna | -6.9172219 | 107.6136188 | OSM: node halte |
| 32 | Rumah Sakit Umum Bungsu | -6.9182109 | 107.6133144 | OSM: node halte |
| 33 | Simpang Embong - Veteran | -6.919936 | 107.6155793 | OSM: node halte |
| 34 | Rumah Sakit Murni Teguh Naripan | -6.9207627 | 107.6160069 | OSM: node halte |
| 35 | Simpang Veteran - Sunda | -6.9206701 | 107.6185682 | OSM: node halte |
| 36 | Seberang SMK Negeri 15 Bandung | -6.9224622 | 107.6187771 | OSM: node halte |
| 37 | Simpang Gatot Subroto - Guntur | -6.9228054 | 107.6212105 | OSM: node halte |
| 38 | Simpang Malabar - Gatot Subroto 2 | -6.9240888 | 107.6243079 | OSM: node halte |
| 39 | Taman Pers Malabar 2 | -6.9256325 | 107.6238594 | OSM: node halte |
| 40 | Seberang SD Al-Azhar 36 Bandung | -6.9273912 | 107.6233363 | OSM: node halte |
| 41 | Simpang Talaga Bodas - Patuha | -6.9287798 | 107.6238453 | OSM: node halte |
| 42 | Seberang Jalan Kangkung | -6.9308795 | 107.6262234 | OSM: node halte |
| 43 | Seberang Dinas Ketenagakerjaan Kota Bandung | -6.9327915 | 107.6265121 | OSM: node halte |
| 44 | Sesko TNI | -6.9334024 | 107.6288798 | OSM: node halte |
| 45 | Simpang Reog - Martanegara | -6.9346225 | 107.6325883 | OSM: node halte |
| 46 | Jalan Reog 1 | -6.935016501594872 | 107.63235289834515 | Diberikan |
| 47 | Kantor Kelurahan Turangga Jalan Reog | -6.9394412 | 107.6310884 | OSM: node halte |
| 48 | SMK Negeri 4 Bandung | -6.9412489 | 107.6285836 | OSM: node halte |
| 49 | Seberang Institut Seni Budaya Indonesia (ISBI) Bandung | -6.9426484 | 107.6282551 | OSM: node halte |
| 50 | Jalan Kayuagung II | -6.944939 | 107.6304936 | OSM: node halte |
| 51 | Jalan Guntursari Wetan | -6.9465077 | 107.6319841 | OSM: node halte |
| 52 | Simpang Buah Batu Soekarno Hatta I | -6.9474617 | 107.6348776 | OSM: node halte |
| 53 | Sekelimus 1 | -6.9463564 | 107.6384357 | OSM: node halte |
| 54 | Simpang Soetta Kiaracondong 2 | -6.945948 | 107.6408655 | OSM: node halte |

## Feeder 2 — K2

Data rute final dan koordinat feeder 2 belum diberikan. Daftar sebelumnya di `008_corridor_route_stops.sql` tetap ditampilkan sebagai **dummy** dan tidak dipakai untuk penentuan koridor spasial, kandidat virtual stop, atau penugasan stop.
