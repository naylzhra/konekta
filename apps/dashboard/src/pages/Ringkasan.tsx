import { useEffect, useState, type ReactNode } from "react";
import { Link } from "react-router-dom";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Line,
  LineChart,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import DemandMap from "../components/map/DemandMap";
import { useDashboard } from "../layout/AppLayout";
import { fetchVirtualStopCandidates, type VirtualStopCandidate } from "../services/api";
import {
  DECISIONS,
  EVALUATION,
  FORECAST,
  HOURLY_DEMAND,
  corridorsFor,
  periodFactor,
} from "../data/simulated";
import "./Ringkasan.css";

const STATUS_LABEL: Record<string, string> = {
  proposed: "Menunggu",
  approved: "Disetujui",
  rejected: "Ditolak",
  superseded: "Digantikan",
};

const CHART_TICK = { fill: "#7a7581", fontSize: 10 };
const PEAK_HOURS = new Set(["07.00", "17.30"]);

function Card({
  title,
  tag,
  className = "",
  children,
}: {
  title: string;
  tag?: ReactNode;
  className?: string;
  children: ReactNode;
}) {
  return (
    <section className={"card " + className}>
      <div className="card__head">
        <h2>{title}</h2>
        {tag && <div className="card__tag">{tag}</div>}
      </div>
      {children}
    </section>
  );
}

function formatNumber(value: number, digits = 0) {
  return value.toLocaleString("id-ID", { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

export default function Ringkasan() {
  const { token, period, corridor, showDetail } = useDashboard();
  const [weekend, setWeekend] = useState(false);
  const [candidates, setCandidates] = useState<VirtualStopCandidate[] | null>(null);
  const [candidateError, setCandidateError] = useState(false);

  useEffect(() => {
    fetchVirtualStopCandidates(token)
      .then((response) => {
        setCandidates(response.items);
        setCandidateError(false);
      })
      .catch(() => setCandidateError(true));
  }, [token]);

  const factor = periodFactor(period);
  const selected = corridorsFor(corridor);
  const passengers = Math.round(selected.reduce((sum, c) => sum + c.passengers, 0) * factor);
  const average = (key: "loadFactor" | "speed" | "travelTime") =>
    selected.reduce((sum, c) => sum + c[key], 0) / selected.length;
  const context = `Bandung ${period}. `;

  const kpis: { label: string; value: string; unit: string; change: string }[] = [
    { label: "Penumpang / hari", value: formatNumber(passengers), unit: "", change: "↑ 18,6%" },
    { label: "Load factor", value: formatNumber(average("loadFactor"), 1), unit: "%", change: "↑ 8,2 pp" },
    { label: "Waktu tempuh", value: formatNumber(average("travelTime"), 1), unit: "menit", change: "↓ 12,5%" },
    { label: "Kecepatan", value: formatNumber(average("speed"), 1), unit: "km/jam", change: "↑ 6,4%" },
    { label: "Waktu tunggu", value: "9", unit: "menit", change: "↓ 40,0%" },
    { label: "Demand terlayani", value: "92", unit: "%", change: "↑ 14 pp" },
  ];

  const topCandidates = (candidates ?? [])
    .slice()
    .sort((a, b) => Number(b.status === "proposed") - Number(a.status === "proposed") || (b.score ?? 0) - (a.score ?? 0))
    .slice(0, 3);
  const pendingCount = (candidates ?? []).filter((c) => c.status === "proposed").length;

  const hourly = HOURLY_DEMAND.map((h) => ({ ...h, trips: Number((h.trips * factor).toFixed(2)) }));
  const forecast = FORECAST.map((f) => ({
    ...f,
    actual: f.actual === undefined ? undefined : Number((f.actual * factor).toFixed(1)),
    forecast: f.forecast === undefined ? undefined : Number((f.forecast * factor).toFixed(1)),
  }));
  const forecastTotal = Math.round(passengers * 1.147);

  return (
    <div className="overview">
      <section className="overview__kpis">
        {kpis.map((kpi) => (
          <article className="kpi" key={kpi.label}>
            <span className="kpi__label">{kpi.label}</span>
            <div className="kpi__value">
              <strong>{kpi.value}</strong>
              <small>{kpi.unit}</small>
            </div>
            <span className={"chip-change" + (kpi.change.startsWith("↓") ? " chip-change--down" : "")}>
              {kpi.change}
            </span>
          </article>
        ))}
      </section>

      <div className="overview__row overview__row--top">
        <Card
          title="Persebaran demand"
          className="card--map"
          tag={
            <div className="segmented" role="group" aria-label="Jenis hari">
              {[
                ["Hari kerja", false],
                ["Akhir pekan", true],
              ].map(([label, value]) => (
                <button
                  key={String(label)}
                  type="button"
                  className={weekend === value ? "is-selected" : ""}
                  aria-pressed={weekend === value}
                  onClick={() => setWeekend(value as boolean)}
                >
                  {label}
                </button>
              ))}
            </div>
          }
        >
          <DemandMap
            periodFactor={factor}
            weekend={weekend}
            onSelect={(area, trips) =>
              showDetail(
                `${area}: ${formatNumber(trips)} perjalanan/hari (${weekend ? "akhir pekan" : "hari kerja"}). ` +
                  `${context}Peta keseluruhan Bandung, tidak difilter per koridor.`,
              )
            }
          />
        </Card>

        <Card
          title="Rekomendasi Titik Bayangan"
          tag={candidates ? `${pendingCount} menunggu persetujuan` : undefined}
        >
          <div className="stop-list">
            {candidateError && <p className="card__empty">Daftar kandidat belum dapat dimuat.</p>}
            {!candidateError && candidates === null && <p className="card__empty">Memuat kandidat…</p>}
            {!candidateError && candidates?.length === 0 && (
              <p className="card__empty">Belum ada hasil analisis permintaan.</p>
            )}
            {topCandidates.map((c) => (
              <button
                key={c.id}
                type="button"
                className="stop-list__item"
                onClick={() =>
                  showDetail(
                    `Kandidat ${c.corridor_id} arah ${c.direction}, slot ${c.time_slot}: ${c.cluster.size} permintaan ` +
                      `dari ${c.unique_users} pengguna unik, skor ${c.score ?? "—"}. ` +
                      `Status: ${STATUS_LABEL[c.status] ?? c.status}. Lokasi ${c.lat.toFixed(5)}, ${c.lng.toFixed(5)}.`,
                  )
                }
              >
                <span className="route-id">{c.corridor_id}</span>
                <span className="stop-list__copy">
                  <span>
                    <strong>
                      {c.direction} · slot {c.time_slot}
                    </strong>
                    <small className={"status-pill status-pill--" + c.status}>
                      {STATUS_LABEL[c.status] ?? c.status}
                    </small>
                  </span>
                  <small>
                    {c.cluster.size} permintaan · {c.unique_users} pengguna unik
                  </small>
                </span>
                <span className="stop-list__score">
                  {c.score ?? "—"}
                  <small>Skor</small>
                </span>
              </button>
            ))}
          </div>
          <Link className="card__link card__link--footer" to="/titik-bayangan">
            Lihat semua ↗
          </Link>
        </Card>

        <Card title="Evaluasi KONEKTA" tag="Baseline → skenario">
          <div className="eval-list">
            {EVALUATION.map((e) => (
              <div key={e.label}>
                <div className="eval-list__row">
                  <strong>{e.label}</strong>
                  <span>{e.value}</span>
                  <b>{e.change}</b>
                </div>
                <div className="eval-list__bars" title={`Baseline ${e.before} · KONEKTA ${e.after}`}>
                  <i className="bar bar--baseline" style={{ width: `${e.before}%` }} />
                  <i className="bar bar--scenario" style={{ width: `${e.after}%` }} />
                </div>
              </div>
            ))}
          </div>
          <div className="eval-legend">
            <span>
              <i className="bar--baseline" /> Baseline
            </span>
            <span>
              <i className="bar--scenario" /> KONEKTA
            </span>
          </div>
          <button
            type="button"
            className="card__link"
            onClick={() =>
              showDetail(
                context +
                  "Baseline: static stop. Skenario: static stop + adaptive virtual stop + pooling. Durasi 1 rit: " +
                  "78,2 → 68,4 menit; pemberhentian: 12 → 10; penumpang per perjalanan: 8,2 → 11,4. Perlu validasi biaya operasi.",
              )
            }
          >
            Semua indikator ↗
          </button>
        </Card>
      </div>

      <div className="overview__row overview__row--middle">
        <Card title="Kinerja per koridor" tag={`${selected.length} koridor`}>
          <div className="table-scroll">
            <table className="data-table">
              <thead>
                <tr>
                  {["Koridor", "Penumpang/hari", "Load factor", "Kecepatan", "Waktu", "Status"].map((h) => (
                    <th key={h}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {selected.map((c) => {
                  const status = c.loadFactor > 80 ? "attention" : c.loadFactor < 60 ? "evaluate" : "good";
                  const label = { attention: "Perhatian", evaluate: "Evaluasi", good: "Optimal" }[status];
                  return (
                    <tr key={c.id}>
                      <td>
                        <span className="route-id">{c.id}</span>
                        <strong>{c.name}</strong>
                      </td>
                      <td>{formatNumber(Math.round(c.passengers * factor))}</td>
                      <td>
                        <span className="lf-bar">
                          <i style={{ width: `${c.loadFactor}%` }} />
                        </span>
                        {c.loadFactor}%
                      </td>
                      <td>{formatNumber(c.speed, 1)} km/jam</td>
                      <td>{c.travelTime} mnt</td>
                      <td>
                        <button
                          type="button"
                          className={"route-status route-status--" + status}
                          onClick={() =>
                            showDetail(
                              `${context}${c.id} · ${c.name}: ${c.loadFactor}% load factor. ` +
                                (c.loadFactor > 80
                                  ? "Prioritas kapasitas pada jam sibuk."
                                  : "Pantau frekuensi dan naik-turun per segmen."),
                            )
                          }
                        >
                          {label} ↗
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Card>

        <Card title="Demand per jam" tag="Ribu perjalanan">
          <div className="chart-box">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={hourly} margin={{ top: 8, right: 4, bottom: 0, left: -24 }}>
                <CartesianGrid vertical={false} stroke="#eae7ef" strokeDasharray="3 3" />
                <XAxis dataKey="hour" tick={CHART_TICK} tickLine={false} axisLine={false} interval={2} />
                <YAxis tick={CHART_TICK} tickLine={false} axisLine={false} tickFormatter={(v) => `${v}k`} />
                <Tooltip
                  cursor={{ fill: "#f6f1ff" }}
                  formatter={(v: number) => [`${formatNumber(v * 1000)} perjalanan`, "Demand"]}
                  labelFormatter={(l) => `Pukul ${l}`}
                />
                <Bar dataKey="trips" radius={[4, 4, 0, 0]} maxBarSize={18}>
                  {hourly.map((h) => (
                    <Cell key={h.hour} fill={PEAK_HOURS.has(h.hour) ? "#5e498f" : "#d1bcff"} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
          <div className="card__foot">
            <span>
              Pagi <strong>{formatNumber(2800 * factor)}</strong>
            </span>
            <span>
              Sore <strong>{formatNumber(2600 * factor)}</strong>
            </span>
            <span>
              Sepi <strong>10–14 WIB</strong>
            </span>
          </div>
        </Card>
      </div>

      <div className="overview__row overview__row--bottom">
        <Card title="Prediksi demand" tag="Ilustrasi XGBoost · model belum aktif">
          <div className="forecast-head">
            <strong>
              {formatNumber(forecastTotal)}
              <small> perjalanan / hari</small>
            </strong>
            <span className="chip-change">+14,7%</span>
            <span className="forecast-legend">
              <i className="forecast-legend__solid" /> Historis
              <i className="forecast-legend__dashed" /> Prediksi
            </span>
          </div>
          <div className="chart-box chart-box--short">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={forecast} margin={{ top: 6, right: 8, bottom: 0, left: -24 }}>
                <CartesianGrid vertical={false} stroke="#eae7ef" strokeDasharray="3 3" />
                <XAxis dataKey="day" tick={CHART_TICK} tickLine={false} axisLine={false} interval={4} />
                <YAxis tick={CHART_TICK} tickLine={false} axisLine={false} tickFormatter={(v) => `${v}k`} domain={["dataMin - 1", "dataMax + 1"]} />
                <ReferenceLine x="Hari ini" stroke="#cbc4d1" strokeDasharray="3 3" />
                <Tooltip formatter={(v: number, name) => [`${formatNumber(v * 1000)} perjalanan`, name === "actual" ? "Historis" : "Prediksi"]} />
                <Line type="monotone" dataKey="actual" stroke="#5e498f" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                <Line type="monotone" dataKey="forecast" stroke="#5e498f" strokeWidth={2} strokeDasharray="5 4" dot={false} activeDot={{ r: 4 }} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </Card>

        <Card title="Rekomendasi keputusan" tag="Perlu validasi">
          <div className="decision-list">
            {DECISIONS.map((d) => (
              <button
                key={d.id}
                type="button"
                onClick={() =>
                  showDetail(
                    `${context}${d.title}. ${d.note}. Rekomendasi ilustratif, bukan keluaran model aktif; ` +
                      "memerlukan kajian Dishub sebelum pelaksanaan.",
                  )
                }
              >
                <span>{d.id}</span>
                <div>
                  <strong>{d.title}</strong>
                  <small>{d.note}</small>
                </div>
                <span>↗</span>
              </button>
            ))}
          </div>
        </Card>
      </div>
    </div>
  );
}
