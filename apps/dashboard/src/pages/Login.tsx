import { useState, type FormEvent } from "react";
import logo from "../assets/logo.png";
import logoWhite from "../assets/logo_putih.png";
import "./Login.css";

type Props = {
  onLogin: (phoneNumber: string, password: string) => Promise<void>;
};

function EyeIcon({ off }: { off: boolean }) {
  return (
    <svg
      width="20"
      height="20"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z" />
      <circle cx="12" cy="12" r="3" />
      {off && <line x1="3" y1="3" x2="21" y2="21" />}
    </svg>
  );
}

export default function Login({ onLogin }: Props) {
  const [phone, setPhone] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
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
    <div className="login">
      <aside className="login__brand">
        <img src={logoWhite} alt="KONEKTA" className="login__brand-logo" />
        <div className="login__brand-copy">
          <h2>Pantau layanan feeder Bandung secara real-time</h2>
          <p>
            Lihat sebaran permintaan, titik jemput virtual, dan posisi armada feeder dalam satu
            dasbor operasional.
          </p>
        </div>
      </aside>

      <main className="login__panel">
        <form className="login__form" onSubmit={handleSubmit} noValidate>
          <img src={logo} alt="KONEKTA" className="login__logo" />
          <h1 className="login__title">Masuk ke Dasbor</h1>
          <p className="login__subtitle">Gunakan akun pemerintah yang terdaftar.</p>

          <label htmlFor="phone" className="login__label">
            Nomor Telepon
          </label>
          <div className="login__field">
            <span className="login__prefix">+62</span>
            <input
              id="phone"
              className="login__input"
              inputMode="numeric"
              autoComplete="tel-national"
              value={phone}
              onChange={(e) => setPhone(e.target.value.replace(/\D/g, "").slice(0, 12))}
            />
          </div>

          <label htmlFor="password" className="login__label">
            Kata Sandi
          </label>
          <div className="login__field">
            <div className="login__password">
              <input
                id="password"
                className="login__input"
                type={showPassword ? "text" : "password"}
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
              <button
                type="button"
                className="login__toggle"
                onClick={() => setShowPassword((v) => !v)}
                aria-label={showPassword ? "Sembunyikan kata sandi" : "Tampilkan kata sandi"}
              >
                <EyeIcon off={!showPassword} />
              </button>
            </div>
          </div>

          {error && (
            <p className="login__error" role="alert">
              {error}
            </p>
          )}

          <button type="submit" className="login__submit" disabled={submitting}>
            {submitting ? "Memuat..." : "Masuk"}
          </button>
        </form>
      </main>
    </div>
  );
}
