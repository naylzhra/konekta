// Simulated Bandung data for the Ringkasan page, lifted from the Figma Make
// prototype. TODO: replace with gateway / forecasting-service endpoints once
// they expose corridor performance, hourly demand and demand-by-area.

export type Corridor = {
  id: string;
  name: string;
  passengers: number;
  loadFactor: number;
  speed: number;
  travelTime: number;
};

export const CORRIDORS: Corridor[] = [
  { id: "K01", name: "Dago – Stasiun Bandung", passengers: 8240, loadFactor: 78, speed: 24.5, travelTime: 32 },
  { id: "K02", name: "Leuwipanjang – Cicaheum", passengers: 6180, loadFactor: 86, speed: 21.2, travelTime: 41 },
  { id: "K03", name: "Antapani – Ciroyom", passengers: 5460, loadFactor: 65, speed: 26.8, travelTime: 35 },
  { id: "K04", name: "Ledeng – Dipatiukur", passengers: 4920, loadFactor: 54, speed: 28.1, travelTime: 29 },
];

export const ALL_CORRIDORS = "Semua koridor";
export const PERIODS = ["2024", "2023"];

export function periodFactor(period: string) {
  return period === "2023" ? 0.86 : 1;
}

export function corridorsFor(corridor: string) {
  return CORRIDORS.filter((c) => corridor === ALL_CORRIDORS || corridor === c.id);
}

// Thousands of trips per 90-minute bucket, 04.00–22.00.
export const HOURLY_DEMAND = [
  { hour: "04.00", trips: 0.4 },
  { hour: "05.30", trips: 1.0 },
  { hour: "07.00", trips: 2.8 },
  { hour: "08.30", trips: 2.2 },
  { hour: "10.00", trips: 1.2 },
  { hour: "11.30", trips: 0.9 },
  { hour: "13.00", trips: 1.1 },
  { hour: "14.30", trips: 1.3 },
  { hour: "16.00", trips: 1.9 },
  { hour: "17.30", trips: 2.6 },
  { hour: "19.00", trips: 2.0 },
  { hour: "20.30", trips: 0.9 },
];

export const FORECAST = [
  { day: "H-9", actual: 13.1 },
  { day: "H-8", actual: 14.0 },
  { day: "H-7", actual: 13.4 },
  { day: "H-6", actual: 15.6 },
  { day: "H-5", actual: 15.0 },
  { day: "H-4", actual: 17.0 },
  { day: "H-3", actual: 15.9 },
  { day: "H-2", actual: 16.8 },
  { day: "H-1", actual: 16.2 },
  { day: "Hari ini", actual: 17.8, forecast: 17.8 },
  { day: "H+1", forecast: 17.2 },
  { day: "H+2", forecast: 18.4 },
  { day: "H+3", forecast: 17.4 },
  { day: "H+4", forecast: 18.7 },
  { day: "H+5", forecast: 18.0 },
  { day: "H+6", forecast: 19.4 },
];

export const EVALUATION = [
  { label: "Jarak akses", value: "450 → 280 m", before: 100, after: 62, change: "−37,8%" },
  { label: "Waktu tunggu", value: "15 → 9 mnt", before: 100, after: 60, change: "−40,0%" },
  { label: "Waktu tempuh", value: "39,1 → 34,2 mnt", before: 100, after: 87, change: "−12,5%" },
  { label: "Load factor", value: "64,2 → 72,4%", before: 64, after: 72, change: "+8,2 pp" },
];

export const DECISIONS = [
  { id: "01", title: "K02 · Tambah 2 armada pagi", note: "06.00–08.00 · Uji kapasitas" },
  { id: "02", title: "Dipatiukur · Uji virtual stop", note: "Validasi demand & keselamatan" },
  { id: "03", title: "K04 · Evaluasi frekuensi", note: "Load factor 54% · redistribusi armada" },
];

// Trips/day starting in each kecamatan on a weekday, and the weekend
// multiplier. Keys match `name` in bandung-kecamatan.json.
export const KECAMATAN_DEMAND: Record<string, { trips: number; weekend: number }> = {
  "Andir": { trips: 1720, weekend: 0.78 },
  "Antapani": { trips: 3660, weekend: 0.8 },
  "Arcamanik": { trips: 1080, weekend: 0.84 },
  "Astanaanyar": { trips: 3860, weekend: 0.89 },
  "Babakan Ciparay": { trips: 2350, weekend: 0.83 },
  "Bandung Kidul": { trips: 1350, weekend: 0.89 },
  "Bandung Kulon": { trips: 1180, weekend: 0.8 },
  "Bandung Wetan": { trips: 5390, weekend: 0.89 },
  "Batununggal": { trips: 2900, weekend: 0.79 },
  "Bojongloa Kaler": { trips: 2680, weekend: 0.9 },
  "Bojongloa Kidul": { trips: 3140, weekend: 0.85 },
  "Buahbatu": { trips: 1090, weekend: 0.86 },
  "Cibeunying Kaler": { trips: 2320, weekend: 0.91 },
  "Cibeunying Kidul": { trips: 2640, weekend: 0.83 },
  "Cibiru": { trips: 620, weekend: 1.4 },
  "Cicendo": { trips: 2070, weekend: 0.79 },
  "Cidadap": { trips: 1200, weekend: 1.14 },
  "Cinambo": { trips: 670, weekend: 1.33 },
  "Coblong": { trips: 3670, weekend: 0.97 },
  "Gedebage": { trips: 880, weekend: 1.32 },
  "Kiaracondong": { trips: 3880, weekend: 0.79 },
  "Lengkong": { trips: 2480, weekend: 0.91 },
  "Mandalajati": { trips: 1210, weekend: 0.83 },
  "Panyileukan": { trips: 580, weekend: 1.39 },
  "Rancasari": { trips: 1280, weekend: 0.89 },
  "Regol": { trips: 2250, weekend: 0.89 },
  "Sukajadi": { trips: 2990, weekend: 0.85 },
  "Sukasari": { trips: 1380, weekend: 1.15 },
  "Sumur Bandung": { trips: 5500, weekend: 0.93 },
  "Ujungberung": { trips: 760, weekend: 1.27 },
};
