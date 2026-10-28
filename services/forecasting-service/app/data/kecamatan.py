"""Kecamatan of Kota Bandung used as forecasting areas.

Names match `kecamatan.name` (infra/db/migrations/014_demand_forecasts.sql)
and apps/dashboard/src/data/bandung-kecamatan.json.

`weight` is the assumed relative share of feeder demand originating in each
kecamatan and `weekend` its weekend multiplier. Both are assumptions until
replaced by BPS population / POI data or trial bookings.
"""

KECAMATAN: dict[str, dict[str, float]] = {
    "Andir": {"weight": 1720, "weekend": 0.78},
    "Antapani": {"weight": 3660, "weekend": 0.80},
    "Arcamanik": {"weight": 1080, "weekend": 0.84},
    "Astanaanyar": {"weight": 3860, "weekend": 0.89},
    "Babakan Ciparay": {"weight": 2350, "weekend": 0.83},
    "Bandung Kidul": {"weight": 1350, "weekend": 0.89},
    "Bandung Kulon": {"weight": 1180, "weekend": 0.80},
    "Bandung Wetan": {"weight": 5390, "weekend": 0.89},
    "Batununggal": {"weight": 2900, "weekend": 0.79},
    "Bojongloa Kaler": {"weight": 2680, "weekend": 0.90},
    "Bojongloa Kidul": {"weight": 3140, "weekend": 0.85},
    "Buahbatu": {"weight": 1090, "weekend": 0.86},
    "Cibeunying Kaler": {"weight": 2320, "weekend": 0.91},
    "Cibeunying Kidul": {"weight": 2640, "weekend": 0.83},
    "Cibiru": {"weight": 620, "weekend": 1.40},
    "Cicendo": {"weight": 2070, "weekend": 0.79},
    "Cidadap": {"weight": 1200, "weekend": 1.14},
    "Cinambo": {"weight": 670, "weekend": 1.33},
    "Coblong": {"weight": 3670, "weekend": 0.97},
    "Gedebage": {"weight": 880, "weekend": 1.32},
    "Kiaracondong": {"weight": 3880, "weekend": 0.79},
    "Lengkong": {"weight": 2480, "weekend": 0.91},
    "Mandalajati": {"weight": 1210, "weekend": 0.83},
    "Panyileukan": {"weight": 580, "weekend": 1.39},
    "Rancasari": {"weight": 1280, "weekend": 0.89},
    "Regol": {"weight": 2250, "weekend": 0.89},
    "Sukajadi": {"weight": 2990, "weekend": 0.85},
    "Sukasari": {"weight": 1380, "weekend": 1.15},
    "Sumur Bandung": {"weight": 5500, "weekend": 0.93},
    "Ujungberung": {"weight": 760, "weekend": 1.27},
}

NAMES = sorted(KECAMATAN)

# Feeder service hours (local time, Asia/Jakarta): first departure 05.00,
# last 21.00.
SERVICE_HOURS = list(range(5, 22))
