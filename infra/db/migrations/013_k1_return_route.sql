-- Generated from ROUTES.md by infra/db/generate_feeder_1_route.py.
-- K1 return direction (Pasar Baru ABC -> Simpang Soetta Kiaracondong 2).
-- Route stops gain a direction; corridors.path stays the forward line and
-- return_path holds this one. Safe to re-run. Run
-- `python -m app.cli.sync_k1_route` afterwards for the road geometry.
BEGIN;

ALTER TABLE corridor_route_stops ADD COLUMN IF NOT EXISTS direction TEXT NOT NULL DEFAULT 'forward'
    CHECK (direction IN ('forward', 'backward'));
ALTER TABLE corridor_route_stops DROP CONSTRAINT IF EXISTS corridor_route_stops_pkey;
ALTER TABLE corridor_route_stops ADD PRIMARY KEY (corridor_id, direction, position);
ALTER TABLE corridors ADD COLUMN IF NOT EXISTS return_path geography(LineString, 4326);
ALTER TABLE trip_plans ADD COLUMN IF NOT EXISTS direction TEXT
    CHECK (direction IN ('forward', 'backward'));

DELETE FROM corridor_route_stops WHERE corridor_id = 'K1' AND direction = 'backward';
INSERT INTO corridor_route_stops (corridor_id, direction, position, name, location, stop_id)
SELECT 'K1', 'backward', route.position, route.name,
       ST_SetSRID(ST_MakePoint(route.lng, route.lat), 4326)::geography,
       md5('konekta:K1:backward:stop:' || route.position)::uuid
FROM (VALUES
    (1, 'Pasar Baru ABC', -6.9184052, 107.6048509),
    (2, 'Simpang Banceuy - ABC', -6.918666178927174, 107.60782597161595),
    (3, 'Jalan Braga Gang Cikapundung', -6.917615676996839, 107.60962675865811),
    (4, 'Suniaraja Braga', -6.9161827, 107.6079838),
    (5, 'Perintis Kemerdekaan', -6.9139566, 107.6078989),
    (6, 'Balai Kota Bandung', -6.91284557798161, 107.60953232373434),
    (7, 'Museum Kota Bandung', -6.9100874, 107.609698),
    (8, 'Halte Santa Angela', -6.912630881264027, 107.61087623352441),
    (9, 'Polrestabes Bandung 2', -6.9145594, 107.6116738),
    (10, 'Seberang SMP Negeri 2 Bandung', -6.9136201, 107.6134632),
    (11, 'Paguyuban Pasundan', -6.9113208, 107.6125214),
    (12, 'Dinas Arsip dan Perpustakaan Kota Bandung', -6.9084121, 107.6134452),
    (13, 'Jalan Trunojoyo Riau Junction', -6.9063176, 107.6126748),
    (14, 'Simpang Sultan Tirtayasa - Trunojoyo 2', -6.9031524, 107.613438),
    (15, 'Taman Segitiga Trunojoyo 2', -6.9020021, 107.6152506),
    (16, 'Lapangan Gasibu A', -6.901132, 107.6199289),
    (17, 'Seberang Jalan Melania RRI Bandung', -6.9012477, 107.6233825),
    (18, 'Seberang Museum Geologi', -6.9012818, 107.6211108),
    (19, 'Simpang Cisangkuy - Cimanuk', -6.902942, 107.6222778),
    (20, 'Simpang Cisangkuy - Citarum', -6.903513, 107.623898),
    (21, 'Pet Park', -6.9048721, 107.6264722),
    (22, 'Taman Cibeunying Utara', -6.9046471, 107.6244523),
    (23, 'Simpang Brantas - Cihapit 2', -6.9067733, 107.6243252),
    (24, 'Pasar Cihapit 2', -6.9078879, 107.6229075),
    (25, 'Polsek Bandung Wetan 2', -6.9083314, 107.6215571),
    (26, 'Simpang Menado - Aceh 2', -6.9098693, 107.6210402),
    (27, 'Simpang Menado - Belitung', -6.91225, 107.6201483),
    (28, 'Simpang Gudang Utara - Menado', -6.9152634, 107.6193866),
    (29, 'Simpang Jawa - Sunda', -6.9157989, 107.6174777),
    (30, 'Seberang SMP Negeri 5 Bandung', -6.9151846, 107.6144795),
    (31, 'Simpang Sumatera - Natuna', -6.9172219, 107.6136188),
    (32, 'Rumah Sakit Umum Bungsu', -6.9182109, 107.6133144),
    (33, 'Simpang Embong - Veteran', -6.919936, 107.6155793),
    (34, 'Rumah Sakit Murni Teguh Naripan', -6.9207627, 107.6160069),
    (35, 'Simpang Veteran - Sunda', -6.9206701, 107.6185682),
    (36, 'Seberang SMK Negeri 15 Bandung', -6.9224622, 107.6187771),
    (37, 'Simpang Gatot Subroto - Guntur', -6.9228054, 107.6212105),
    (38, 'Simpang Malabar - Gatot Subroto 2', -6.9240888, 107.6243079),
    (39, 'Taman Pers Malabar 2', -6.9256325, 107.6238594),
    (40, 'Seberang SD Al-Azhar 36 Bandung', -6.9273912, 107.6233363),
    (41, 'Simpang Talaga Bodas - Patuha', -6.9287798, 107.6238453),
    (42, 'Seberang Jalan Kangkung', -6.9308795, 107.6262234),
    (43, 'Seberang Dinas Ketenagakerjaan Kota Bandung', -6.9327915, 107.6265121),
    (44, 'Sesko TNI', -6.9334024, 107.6288798),
    (45, 'Simpang Reog - Martanegara', -6.9346225, 107.6325883),
    (46, 'Jalan Reog 1', -6.935016501594872, 107.63235289834515),
    (47, 'Kantor Kelurahan Turangga Jalan Reog', -6.9394412, 107.6310884),
    (48, 'SMK Negeri 4 Bandung', -6.9412489, 107.6285836),
    (49, 'Seberang Institut Seni Budaya Indonesia (ISBI) Bandung', -6.9426484, 107.6282551),
    (50, 'Jalan Kayuagung II', -6.944939, 107.6304936),
    (51, 'Jalan Guntursari Wetan', -6.9465077, 107.6319841),
    (52, 'Simpang Buah Batu Soekarno Hatta I', -6.9474617, 107.6348776),
    (53, 'Sekelimus 1', -6.9463564, 107.6384357),
    (54, 'Simpang Soetta Kiaracondong 2', -6.945948, 107.6408655)
) AS route(position, name, lat, lng);

INSERT INTO stops (id, type, name, location, corridor_id, valid_until)
SELECT stop_id, 'static'::stop_type, name, location, 'K1', NULL
FROM corridor_route_stops
WHERE corridor_id = 'K1' AND direction = 'backward'
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name, location = EXCLUDED.location, corridor_id = EXCLUDED.corridor_id;

UPDATE corridors
SET return_path = (
    SELECT ST_MakeLine(location::geometry ORDER BY position)::geography
    FROM corridor_route_stops WHERE corridor_id = 'K1' AND direction = 'backward'
)
WHERE id = 'K1';

COMMIT;
