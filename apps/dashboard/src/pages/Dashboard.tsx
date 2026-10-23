import MapView from "../components/map/MapView";
import PerfChart from "../components/charts/PerfChart";
import { useGatewayHealth } from "../hooks/useGatewayHealth";
import { useEffect, useState } from "react";
import { fetchVirtualStopCandidates, type VirtualStopCandidate } from "../services/api";

type Props = {
  onLogout: () => void;
  token: string;
};

export default function Dashboard({ onLogout, token }: Props) {
  const gatewayStatus = useGatewayHealth();
  const [candidates, setCandidates] = useState<VirtualStopCandidate[]>([]);
  const [candidateError, setCandidateError] = useState(false);

  useEffect(() => {
    fetchVirtualStopCandidates(token)
      .then((response) => setCandidates(response.items))
      .catch(() => setCandidateError(true));
  }, [token]);

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100vh" }}>
      <header
        style={{
          padding: "1rem",
          borderBottom: "1px solid #e5e5e5",
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
        }}
      >
        <div>
          <h1 style={{ margin: 0, fontSize: "1.25rem" }}>KONEKTA Ops Dashboard</h1>
          <small>gateway: {gatewayStatus}</small>
        </div>
        <button onClick={onLogout}>Keluar</button>
      </header>
      <div style={{ flex: 1, minHeight: 0 }}>
        <MapView />
      </div>
      <div style={{ height: 280, padding: "1rem" }}>
        <PerfChart />
      </div>
      <section style={{ padding: "1rem", maxHeight: 320, overflowY: "auto" }}>
        <h2>Kandidat virtual stop</h2>
        {candidateError && <p>Daftar kandidat belum dapat dimuat.</p>}
        {!candidateError && candidates.length === 0 && <p>Belum ada hasil analisis permintaan.</p>}
        {candidates.map((candidate) => (
          <article key={candidate.id} style={{ borderTop: "1px solid #ddd", padding: "0.5rem 0" }}>
            <strong>{candidate.corridor_id} · {candidate.direction} · slot {candidate.time_slot}</strong>
            <div>{candidate.status} · {candidate.unique_users} pengguna unik · skor {candidate.score ?? "—"}</div>
            <div>{candidate.lat}, {candidate.lng} · {candidate.action ?? "—"}</div>
            <ul>
              {candidate.evaluation.checks.map((check) => (
                <li key={check.criterion}>{check.criterion}: {check.passed ? "lolos" : "gagal"}{check.detail ? ` (${check.detail})` : ""}</li>
              ))}
            </ul>
          </article>
        ))}
      </section>
    </div>
  );
}
