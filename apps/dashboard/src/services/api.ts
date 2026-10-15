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
    throw new ApiError(body.detail ?? `Request failed (${response.status})`, response.status);
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
