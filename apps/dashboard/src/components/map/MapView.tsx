import { useEffect, useRef } from "react";
import mapboxgl from "mapbox-gl";

// TODO: pull from env (VITE_MAPBOX_TOKEN) once the dashboard talks to real
// spatial data (virtual stops, feeder positions, demand heatmaps).
const MAPBOX_TOKEN = import.meta.env.VITE_MAPBOX_TOKEN ?? "";
mapboxgl.accessToken = MAPBOX_TOKEN;

const BANDUNG_CENTER: [number, number] = [107.6191, -6.9175];

export default function MapView() {
  const containerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    // mapboxgl.Map throws without a token, which would blank the whole page.
    if (!containerRef.current || !MAPBOX_TOKEN) return;

    const map = new mapboxgl.Map({
      container: containerRef.current,
      style: "mapbox://styles/mapbox/light-v11",
      center: BANDUNG_CENTER,
      zoom: 12,
    });

    return () => map.remove();
  }, []);

  if (!MAPBOX_TOKEN) {
    return (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          padding: 16,
          textAlign: "center",
          color: "#666",
        }}
      >
        Peta belum aktif: isi VITE_MAPBOX_TOKEN di apps/dashboard/.env lalu jalankan ulang npm run dev.
      </div>
    );
  }

  return <div ref={containerRef} style={{ width: "100%", height: "100%" }} />;
}
