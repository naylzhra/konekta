import { useEffect, useState } from "react";
import { fetchGatewayHealth } from "../services/api";

type Status = "idle" | "ok" | "error";

// TODO: replace with real data hooks (virtual stops, feeder locations,
// live demand) once those endpoints exist. This just proves dashboard ->
// gateway connectivity for now.
export function useGatewayHealth(): Status {
  const [status, setStatus] = useState<Status>("idle");

  useEffect(() => {
    fetchGatewayHealth()
      .then(() => setStatus("ok"))
      .catch(() => setStatus("error"));
  }, []);

  return status;
}
