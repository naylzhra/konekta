import MapView from "../components/map/MapView";
import PerfChart from "../components/charts/PerfChart";
import { useGatewayHealth } from "../hooks/useGatewayHealth";

export default function Dashboard() {
  const gatewayStatus = useGatewayHealth();

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100vh" }}>
      <header style={{ padding: "1rem", borderBottom: "1px solid #e5e5e5" }}>
        <h1 style={{ margin: 0, fontSize: "1.25rem" }}>KONEKTA Ops Dashboard</h1>
        <small>gateway: {gatewayStatus}</small>
      </header>
      <div style={{ flex: 1, minHeight: 0 }}>
        <MapView />
      </div>
      <div style={{ height: 280, padding: "1rem" }}>
        <PerfChart />
      </div>
    </div>
  );
}
