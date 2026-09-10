import { useEffect, useRef } from "react";
import mapboxgl from "mapbox-gl";

// TODO: pull from env (VITE_MAPBOX_TOKEN) once the dashboard talks to real
// spatial data (virtual stops, feeder positions, demand heatmaps).
mapboxgl.accessToken = import.meta.env.VITE_MAPBOX_TOKEN ?? "";

const BANDUNG_CENTER: [number, number] = [107.6191, -6.9175];

export default function MapView() {
  const containerRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!containerRef.current) return;

    const map = new mapboxgl.Map({
      container: containerRef.current,
      style: "mapbox://styles/mapbox/light-v11",
      center: BANDUNG_CENTER,
      zoom: 12,
    });

    return () => map.remove();
  }, []);

  return <div ref={containerRef} style={{ width: "100%", height: "100%" }} />;
}
