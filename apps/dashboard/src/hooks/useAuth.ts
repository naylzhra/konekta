import { useCallback, useEffect, useState } from "react";
import { ApiError, DASHBOARD_ROLE, fetchMe, login as apiLogin, logout as apiLogout } from "../services/api";

const TOKEN_KEY = "konekta.dashboard.token";

export type AuthState = "checking" | "signed-out" | "signed-in";

function readToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

function writeToken(token: string | null) {
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token);
    else localStorage.removeItem(TOKEN_KEY);
  } catch {
    // storage unavailable
  }
}

export function useAuth() {
  const [token, setToken] = useState<string | null>(readToken);
  const [state, setState] = useState<AuthState>(token ? "checking" : "signed-out");

  useEffect(() => {
    if (state !== "checking" || !token) return;
    fetchMe(token)
      .then((me) => {
        if (me.role === DASHBOARD_ROLE) {
          setState("signed-in");
        } else {
          writeToken(null);
          setToken(null);
          setState("signed-out");
        }
      })
      .catch((err) => {
        if (err instanceof ApiError) {
          writeToken(null);
          setToken(null);
          setState("signed-out");
        } else {
          setState("signed-in");
        }
      });
  }, [state, token]);

  const login = useCallback(async (phoneNumber: string, password: string) => {
    let result;
    try {
      result = await apiLogin(phoneNumber, password);
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) throw new Error("Nomor telepon atau kata sandi salah");
      if (err instanceof ApiError && err.status === 403) throw new Error("Akun Anda ditangguhkan");
      if (err instanceof ApiError) throw new Error("Terjadi kesalahan. Silakan coba lagi.");
      throw new Error("Tidak dapat terhubung ke server.");
    }

    if (result.role !== DASHBOARD_ROLE) {
      await apiLogout(result.token).catch(() => {});
      throw new Error("Akun ini tidak memiliki akses ke dashboard. Gunakan aplikasi mobile KONEKTA.");
    }

    writeToken(result.token);
    setToken(result.token);
    setState("signed-in");
  }, []);

  const logout = useCallback(async () => {
    if (token) await apiLogout(token).catch(() => {});
    writeToken(null);
    setToken(null);
    setState("signed-out");
  }, [token]);

  return { state, token, login, logout };
}
