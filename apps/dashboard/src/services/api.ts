const GATEWAY_BASE_URL = import.meta.env.VITE_GATEWAY_URL ?? "http://localhost:8000";

export async function fetchGatewayHealth(): Promise<{ status: string; service: string }> {
  const response = await fetch(`${GATEWAY_BASE_URL}/health`);
  if (!response.ok) {
    throw new Error(`Gateway health check failed: ${response.status}`);
  }
  return response.json();
}
