const GATEWAY_BASE_URL = import.meta.env.VITE_GATEWAY_URL ?? "http://localhost:8000";

export const DASHBOARD_ROLE = "government";

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

async function request<T>(path: string, init: RequestInit = {}, token?: string): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.body) headers.set("Content-Type", "application/json");
  if (token) headers.set("Authorization", `Bearer ${token}`);

  const response = await fetch(`${GATEWAY_BASE_URL}${path}`, { ...init, headers });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail = body.detail;
    const message = typeof detail === "string" ? detail
      : typeof detail?.message === "string" ? detail.message
      : `Request failed (${response.status})`;
    throw new ApiError(message, response.status);
  }
  return body as T;
}

export function fetchGatewayHealth(): Promise<{ status: string; service: string }> {
  return request("/health");
}

export function login(phoneNumber: string, password: string): Promise<{ token: string; role: string }> {
  return request("/auth/login", {
    method: "POST",
    body: JSON.stringify({ phone_number: phoneNumber, password }),
  });
}

export function fetchMe(token: string): Promise<{ user_id: string; role: string; status: string }> {
  return request("/auth/me", {}, token);
}

export function logout(token: string): Promise<{ status: string }> {
  return request("/auth/logout", { method: "POST" }, token);
}

export type VirtualStopCandidate = {
  id: string;
  status: string;
  eligible: boolean;
  corridor_id: string;
  direction: string;
  time_slot: number;
  unique_users: number;
  cluster: { size: number };
  score: number | null;
  action: string | null;
  lat: number;
  lng: number;
  evaluation: {
    checks: { criterion: string; passed: boolean; detail?: string | null }[];
  };
};

export function fetchVirtualStopCandidates(token: string): Promise<{ items: VirtualStopCandidate[] }> {
  return request("/virtual-stops/candidates", {}, token);
}

export function reviewVirtualStopCandidate(
  token: string,
  candidateId: string,
  decision: "approve" | "reject",
  reviewNote?: string,
): Promise<{ id: string; status: string; stop_id?: string }> {
  return request(`/virtual-stops/candidates/${encodeURIComponent(candidateId)}/${decision}`, {
    method: "POST",
    body: JSON.stringify({ review_note: reviewNote || null }),
  }, token);
}
