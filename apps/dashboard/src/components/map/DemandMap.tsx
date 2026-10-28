import { useEffect, useMemo, useRef, useState } from "react";
import mapboxgl, { type GeoJSONSource } from "mapbox-gl";
import { KECAMATAN_DEMAND } from "../../data/simulated";
// Kecamatan boundaries of Kota Bandung from OpenStreetMap (© OpenStreetMap
// contributors, ODbL), simplified to ~13 m.
import kecamatan from "../../data/bandung-kecamatan.json";
import "./DemandMap.css";

const MAPBOX_TOKEN = import.meta.env.VITE_MAPBOX_TOKEN ?? "";
mapboxgl.accessToken = MAPBOX_TOKEN;

const BANDUNG_BOUNDS: [[number, number], [number, number]] = [
  [107.545, -6.975],
  [107.74, -6.835],
];

// Sequential single-hue ramp (light → dark) from the KONEKTA purple family.
export const DEMAND_CLASSES = [
  { min: 0, color: "#ebe4ff", label: "< 1.000" },
  { min: 1000, color: "#c9b5f5" },
  { min: 2000, color: "#9a80cc" },
  { min: 3000, color: "#6a52a0" },
  { min: 4000, color: "#2e2b56", label: "4.000+" },
];

type Props = {
  periodFactor: number;
  weekend: boolean;
  onSelect: (area: string, trips: number) => void;
};

type Area = { area: string; trips: number };

const boundaries = kecamatan as GeoJSON.FeatureCollection<GeoJSON.Polygon | GeoJSON.MultiPolygon, { name: string }>;

function withDemand(factor: number, weekend: boolean): GeoJSON.FeatureCollection {
  return {
    ...boundaries,
    features: boundaries.features.map((f) => {
      const demand = KECAMATAN_DEMAND[f.properties.name];
      const trips = demand ? Math.round(demand.trips * (weekend ? demand.weekend : 1) * factor) : 0;
      return { ...f, properties: { ...f.properties, trips } };
    }),
  };
}

const fillColor: mapboxgl.Expression = [
  "step",
  ["get", "trips"],
  DEMAND_CLASSES[0].color,
  ...DEMAND_CLASSES.slice(1).flatMap((c) => [c.min, c.color]),
];

export default function DemandMap({ periodFactor, weekend, onSelect }: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<mapboxgl.Map | null>(null);
  const onSelectRef = useRef(onSelect);
  onSelectRef.current = onSelect;
  const [hovered, setHovered] = useState<Area | null>(null);

  const data = useMemo(() => withDemand(periodFactor, weekend), [periodFactor, weekend]);
  const dataRef = useRef(data);
  dataRef.current = data;

  const peak = useMemo(
    () =>
      data.features.reduce<Area>(
        (best, f) => (f.properties!.trips > best.trips ? { area: f.properties!.name, trips: f.properties!.trips } : best),
        { area: "", trips: 0 },
      ),
    [data],
  );

  useEffect(() => {
    if (!containerRef.current || !MAPBOX_TOKEN) return;

    const map = new mapboxgl.Map({
      container: containerRef.current,
      style: "mapbox://styles/mapbox/light-v11",
      bounds: BANDUNG_BOUNDS,
      cooperativeGestures: true,
      attributionControl: false,
    });
    mapRef.current = map;
    map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), "top-right");
    map.addControl(new mapboxgl.AttributionControl({ compact: true }));

    let hoverId: string | number | undefined;

    map.on("load", () => {
      map.addSource("demand", { type: "geojson", data: dataRef.current, promoteId: "name" });
      // Insert below the basemap's labels so street names stay readable.
      const firstLabel = map.getStyle().layers?.find((l) => l.type === "symbol")?.id;
      map.addLayer(
        {
          id: "demand-fill",
          type: "fill",
          source: "demand",
          paint: {
            "fill-color": fillColor,
            "fill-opacity": ["case", ["boolean", ["feature-state", "hover"], false], 0.92, 0.8],
          },
        },
        firstLabel,
      );
      map.addLayer(
        {
          id: "demand-outline",
          type: "line",
          source: "demand",
          paint: { "line-color": "#ffffff", "line-width": 1.2 },
        },
        firstLabel,
      );
      map.addLayer({
        id: "demand-hover",
        type: "line",
        source: "demand",
        paint: {
          "line-color": "#006972",
          "line-width": ["case", ["boolean", ["feature-state", "hover"], false], 2.5, 0],
        },
      });
    });

    map.on("mousemove", "demand-fill", (e) => {
      const feature = e.features?.[0];
      if (!feature) return;
      if (hoverId !== undefined) map.setFeatureState({ source: "demand", id: hoverId }, { hover: false });
      hoverId = feature.id;
      if (hoverId !== undefined) map.setFeatureState({ source: "demand", id: hoverId }, { hover: true });
      map.getCanvas().style.cursor = "pointer";
      setHovered({ area: feature.properties!.name, trips: feature.properties!.trips });
    });

    map.on("mouseleave", "demand-fill", () => {
      if (hoverId !== undefined) map.setFeatureState({ source: "demand", id: hoverId }, { hover: false });
      hoverId = undefined;
      map.getCanvas().style.cursor = "";
      setHovered(null);
    });

    map.on("click", "demand-fill", (e) => {
      const props = e.features?.[0]?.properties;
      if (props) onSelectRef.current(props.name, props.trips);
    });

    return () => {
      map.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    const source = mapRef.current?.getSource("demand") as GeoJSONSource | undefined;
    source?.setData(data);
  }, [data]);

  if (!MAPBOX_TOKEN) {
    return (
      <div className="demand-map demand-map--empty">
        Peta belum aktif: isi VITE_MAPBOX_TOKEN di apps/dashboard/.env lalu jalankan ulang npm run dev.
      </div>
    );
  }

  const readout = hovered ?? peak;

  return (
    <div className="demand-map">
      <div ref={containerRef} className="demand-map__canvas" />
      <div className="demand-map__readout">
        <span>{hovered ? "Kecamatan" : "Demand tertinggi"}</span>
        <strong>{readout.area}</strong>
        <b>{readout.trips.toLocaleString("id-ID")} perjalanan/hari</b>
      </div>
      <div className="demand-map__legend" aria-label="Legenda demand perjalanan per hari">
        <span>Perjalanan/hari</span>
        <div className="demand-map__swatches">
          {DEMAND_CLASSES.map((c) => (
            <i key={c.min} style={{ background: c.color }} title={`≥ ${c.min.toLocaleString("id-ID")}`} />
          ))}
        </div>
        <div className="demand-map__scale">
          <span>{DEMAND_CLASSES[0].label}</span>
          <span>{DEMAND_CLASSES[DEMAND_CLASSES.length - 1].label}</span>
        </div>
      </div>
    </div>
  );
}
