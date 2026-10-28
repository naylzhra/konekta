import Dashboard from "./pages/Dashboard";
import Login from "./pages/Login";
import { useAuth } from "./hooks/useAuth";

export default function App() {
  const { state, token, login, logout } = useAuth();

  if (state === "checking") return null;
  if (state === "signed-out") return <Login onLogin={login} />;
  return <Dashboard onLogout={logout} token={token!} />;
}
