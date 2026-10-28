import { useCallback, useEffect, useState } from "react";
import { useDashboard } from "../layout/AppLayout";
import { fetchVirtualStopCandidates, reviewVirtualStopCandidate, type VirtualStopCandidate } from "../services/api";
import "./Ringkasan.css";
import "./TitikBayangan.css";

// TODO: restyle from the Figma Make "Persetujuan Titik Bayangan" screen
// (ApprovalRequests.tsx). For now this is the original review list on the
// new layout.
export default function TitikBayangan() {
  const { token } = useDashboard();
  const [candidates, setCandidates] = useState<VirtualStopCandidate[]>([]);
  const [candidateError, setCandidateError] = useState(false);
  const [reviewError, setReviewError] = useState<string | null>(null);
  const [reviewingId, setReviewingId] = useState<string | null>(null);

  const refreshCandidates = useCallback(async () => {
    try {
      const response = await fetchVirtualStopCandidates(token);
      setCandidates(response.items);
      setCandidateError(false);
    } catch {
      setCandidateError(true);
    }
  }, [token]);

  async function review(candidateId: string, decision: "approve" | "reject") {
    setReviewingId(candidateId);
    setReviewError(null);
    try {
      await reviewVirtualStopCandidate(token, candidateId, decision);
      await refreshCandidates();
    } catch (error) {
      setReviewError(error instanceof Error ? error.message : "Peninjauan gagal.");
    } finally {
      setReviewingId(null);
    }
  }

  useEffect(() => {
    void refreshCandidates();
    const interval = window.setInterval(() => void refreshCandidates(), 30_000);
    return () => window.clearInterval(interval);
  }, [refreshCandidates]);

  return (
    <section className="card approvals">
      <div className="card__head">
        <h2>Kandidat virtual stop</h2>
        <button type="button" className="btn-secondary" onClick={() => void refreshCandidates()}>
          Muat ulang
        </button>
      </div>
      {candidateError && <p className="card__empty">Daftar kandidat belum dapat dimuat.</p>}
      {reviewError && (
        <p className="approvals__error" role="alert">
          {reviewError}
        </p>
      )}
      {!candidateError && candidates.length === 0 && <p className="card__empty">Belum ada hasil analisis permintaan.</p>}
      {candidates.map((candidate) => (
        <article key={candidate.id} className="approvals__item">
          <div className="approvals__title">
            <span className="route-id">{candidate.corridor_id}</span>
            <strong>
              {candidate.direction} · slot {candidate.time_slot}
            </strong>
            <small className={"status-pill status-pill--" + candidate.status}>{candidate.status}</small>
          </div>
          <div className="approvals__meta">
            {candidate.cluster.size} request · {candidate.unique_users} pengguna unik · skor {candidate.score ?? "—"} ·{" "}
            {candidate.lat}, {candidate.lng} · {candidate.action ?? "—"}
          </div>
          <ul className="approvals__checks">
            {candidate.evaluation.checks.map((check) => (
              <li key={check.criterion} className={check.passed ? "is-passed" : "is-failed"}>
                {check.criterion}: {check.passed ? "lolos" : "gagal"}
                {check.detail ? ` (${check.detail})` : ""}
              </li>
            ))}
          </ul>
          {candidate.status === "proposed" && (
            <div className="approvals__actions">
              {candidate.eligible && (
                <button
                  type="button"
                  className="btn-primary"
                  disabled={reviewingId !== null}
                  onClick={() => void review(candidate.id, "approve")}
                >
                  Setujui titik
                </button>
              )}
              <button
                type="button"
                className="btn-secondary"
                disabled={reviewingId !== null}
                onClick={() => void review(candidate.id, "reject")}
              >
                Tolak usulan
              </button>
            </div>
          )}
        </article>
      ))}
    </section>
  );
}
