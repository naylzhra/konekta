import { useState, type CSSProperties, type FormEvent } from "react";

type Props = {
  onLogin: (phoneNumber: string, password: string) => Promise<void>;
};

const inputStyle: CSSProperties = {
  padding: "0.65rem 0.75rem",
  border: "1px solid #d4d4d4",
  borderRadius: 8,
  fontSize: "1rem",
};

export default function Login({ onLogin }: Props) {
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    if (phone.length < 10 || phone.length > 12) {
      setError("Nomor telepon tidak valid");
      return;
    }
    if (!password) {
      setError("Kata sandi wajib diisi");
      return;
    }

    setError(null);
    setSubmitting(true);
    try {
      await onLogin(`+62${phone}`, password);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      setSubmitting(false);
    }
  }

  return (
    <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", padding: "1rem" }}>
      <form
        onSubmit={handleSubmit}
        style={{ width: "100%", maxWidth: 360, display: "flex", flexDirection: "column", gap: "0.75rem" }}
      >
        <h1 style={{ margin: 0, fontSize: "1.5rem" }}>KONEKTA Ops Dashboard</h1>
        <p style={{ margin: "0 0 0.5rem", color: "#737373" }}>Masuk dengan akun pemerintah.</p>

        <label htmlFor="phone">Nomor Telepon</label>
        <div style={{ display: "flex", gap: "0.5rem" }}>
          <span style={{ ...inputStyle, background: "#f5f5f5" }}>+62</span>
          <input
            id="phone"
            inputMode="numeric"
            autoComplete="tel-national"
            value={phone}
            onChange={(e) => setPhone(e.target.value.replace(/\D/g, "").slice(0, 12))}
            style={{ ...inputStyle, flex: 1, minWidth: 0 }}
          />
        </div>

        <label htmlFor="password">Kata Sandi</label>
        <input
          id="password"
          type="password"
          autoComplete="current-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          style={inputStyle}
        />

        {error && <p style={{ margin: 0, color: "#dc2626", fontSize: "0.875rem" }}>{error}</p>}

        <button
          type="submit"
          disabled={submitting}
          style={{
            marginTop: "0.5rem",
            padding: "0.75rem",
            border: "none",
            borderRadius: 8,
            background: "#171717",
            color: "#fff",
            fontSize: "1rem",
            cursor: submitting ? "default" : "pointer",
            opacity: submitting ? 0.6 : 1,
          }}
        >
          {submitting ? "Memuat..." : "Masuk"}
        </button>
      </form>
    </div>
  );
}
