import { Navigate, Route, Routes } from "react-router-dom";
import AppLayout from "./layout/AppLayout";
import AnalisisPerforma from "./pages/AnalisisPerforma";
import Login from "./pages/Login";
import Ringkasan from "./pages/Ringkasan";
import TitikBayangan from "./pages/TitikBayangan";
import { useAuth } from "./hooks/useAuth";

export default function App() {
  const { state, token, login, logout } = useAuth();

  if (state === "checking") return null;
  if (state === "signed-out") return <Login onLogin={login} />;
  return (
    <Routes>
      <Route element={<AppLayout token={token!} onLogout={logout} />}>
        <Route index element={<Ringkasan />} />
        <Route path="analisis" element={<AnalisisPerforma />} />
        <Route path="titik-bayangan" element={<TitikBayangan />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
