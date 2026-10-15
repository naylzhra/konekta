import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

// Placeholder data — TODO: wire to forecasting-service / gateway metrics
// once demand + performance endpoints exist.
const placeholderData = [
  { time: "08:00", demand: 0 },
  { time: "09:00", demand: 0 },
  { time: "10:00", demand: 0 },
  { time: "11:00", demand: 0 },
];

export default function PerfChart() {
  return (
    <ResponsiveContainer width="100%" height="100%">
      <LineChart data={placeholderData}>
        <CartesianGrid strokeDasharray="3 3" />
        <XAxis dataKey="time" />
        <YAxis />
        <Tooltip />
        <Line type="monotone" dataKey="demand" stroke="#2563eb" strokeWidth={2} />
      </LineChart>
    </ResponsiveContainer>
  );
}
