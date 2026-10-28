import { useState } from "react";
import { NavLink, Outlet, useOutletContext } from "react-router-dom";
import Icon, { type IconName } from "../components/Icon";
import { useGatewayHealth } from "../hooks/useGatewayHealth";
import { ALL_CORRIDORS, CORRIDORS, PERIODS, corridorsFor, periodFactor } from "../data/simulated";
import logo from "../assets/logo.png";
import "./AppLayout.css";

export type DashboardContext = {
  token: string;
  period: string;
  corridor: string;
  showDetail: (text: string) => void;
};

export function useDashboard() {
  return useOutletContext<DashboardContext>();
}

const NAV: { to: string; label: string; icon: IconName }[] = [
  { to: "/", label: "Ringkasan", icon: "grid" },
  { to: "/analisis", label: "Analisis Performa & Rute", icon: "chart" },
  { to: "/titik-bayangan", label: "Persetujuan Titik Bayangan", icon: "map" },
];

type Props = {
  token: string;
  onLogout: () => void;
};

export default function AppLayout({ token, onLogout }: Props) {
  const gatewayStatus = useGatewayHealth();
  const [period, setPeriod] = useState(PERIODS[0]);
  const [corridor, setCorridor] = useState(ALL_CORRIDORS);
  const [notice, setNotice] = useState<string | null>(null);
  const [detail, setDetail] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);

  function exportReport() {
    const factor = periodFactor(period);
    const rows = corridorsFor(corridor).map((c) =>
      [c.id, c.name, Math.round(c.passengers * factor), `${c.loadFactor}%`, c.speed, c.travelTime].join(","),
    );
    const csv = ["Koridor,Rute,Penumpang,Load factor,Kecepatan,Waktu tempuh", ...rows].join("\n");
    const link = document.createElement("a");
    link.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
    link.download = `konekta-laporan-${period}.csv`;
    link.click();
    URL.revokeObjectURL(link.href);
    setNotice("Laporan berhasil diunduh.");
  }

  const context: DashboardContext = { token, period, corridor, showDetail: setDetail };

  return (
    <div className="app">
      <header className="topbar">
        <img src={logo} alt="KONEKTA" className="topbar__logo" />

        <nav className="topbar__nav" aria-label="Navigasi utama">
          {NAV.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === "/"}
              className={({ isActive }) => "topbar__nav-item" + (isActive ? " is-active" : "")}
            >
              <Icon name={item.icon} size={16} />
              {item.label}
            </NavLink>
          ))}
        </nav>

        <div className="topbar__identity">
          <strong>Bandung</strong>
        </div>

        <div className="topbar__filters">
          <label className="topbar__period">
            <span>Periode</span>
            <select aria-label="Periode" value={period} onChange={(e) => setPeriod(e.target.value)}>
              {PERIODS.map((p) => (
                <option key={p}>{p}</option>
              ))}
            </select>
          </label>
          <select
            className="topbar__corridor"
            aria-label="Koridor"
            value={corridor}
            onChange={(e) => setCorridor(e.target.value)}
          >
            <option value={ALL_CORRIDORS}>{ALL_CORRIDORS}</option>
            {CORRIDORS.map((c) => (
              <option key={c.id} value={c.id}>
                {c.id} · {c.name}
              </option>
            ))}
          </select>
          <button type="button" className="btn-primary topbar__export" onClick={exportReport}>
            <Icon name="download" size={14} />
            <span>Ekspor laporan</span>
          </button>
        </div>

        <div className="topbar__right">
          {gatewayStatus === "error" && (
            <span className="topbar__status">
              <span className="topbar__status-dot" />
              Gateway terputus
            </span>
          )}
          <button
            type="button"
            className="topbar__icon-button"
            aria-label="Notifikasi"
            onClick={() => setNotice("Belum ada notifikasi baru.")}
          >
            <Icon name="bell" size={18} />
          </button>
          <div className="topbar__account">
            <button
              type="button"
              className="topbar__avatar"
              aria-label="Menu akun"
              aria-expanded={menuOpen}
              onClick={() => setMenuOpen((v) => !v)}
            >
              GV
            </button>
            {menuOpen && (
              <div className="topbar__menu" role="menu">
                <button type="button" role="menuitem" onClick={onLogout}>
                  <Icon name="logout" size={16} />
                  Keluar
                </button>
              </div>
            )}
          </div>
        </div>
      </header>

      <main className="app__main" onClick={() => setMenuOpen(false)}>
        <Outlet context={context} />
      </main>

      {notice && (
        <div className="toast" role="status">
          {notice}
          <button type="button" onClick={() => setNotice(null)} aria-label="Tutup notifikasi">
            ×
          </button>
        </div>
      )}

      {detail && (
        <div className="modal-backdrop" onClick={() => setDetail(null)}>
          <section
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-label="Detail analisis"
            onClick={(e) => e.stopPropagation()}
          >
            <span className="modal__icon">
              <Icon name="chart" />
            </span>
            <h2>Detail analisis</h2>
            <p>{detail}</p>
            <button type="button" className="btn-primary" onClick={() => setDetail(null)}>
              Tutup detail
            </button>
          </section>
        </div>
      )}
    </div>
  );
}
