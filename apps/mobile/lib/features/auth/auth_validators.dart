import '../../core/api/api_client.dart';

/// Client-side validation + error-message translation for the auth flows
/// (login/register). All user-facing text here is Indonesian by product
/// requirement -- this is the one place that owns those strings so they
/// don't drift between login_screen.dart and register_screen.dart.

/// Indonesian mobile numbers are validated as 10-12 digits *after* the
/// fixed "+62" prefix shown separately in the UI. The field itself also
/// blocks non-digit input via FilteringTextInputFormatter.digitsOnly, so
/// this only needs to check length/emptiness.
String? validatePhoneNumber(String value) {
  if (value.isEmpty) return 'Nomor telepon wajib diisi';
  if (value.length < 10 || value.length > 12) {
    return 'Nomor telepon harus terdiri dari 10-12 digit';
  }
  return null;
}

final _hasDigit = RegExp(r'[0-9]');
final _hasSpecialChar = RegExp(r'[^A-Za-z0-9]');

/// Password policy: minimum 8 characters, at least 1 digit, at least 1
/// special (non-alphanumeric) character.
String? validatePassword(String value) {
  if (value.isEmpty) return 'Kata sandi wajib diisi';
  if (value.length < 8) return 'Kata sandi minimal 8 karakter';
  if (!_hasDigit.hasMatch(value)) {
    return 'Kata sandi harus mengandung minimal 1 angka';
  }
  if (!_hasSpecialChar.hasMatch(value)) {
    return 'Kata sandi harus mengandung minimal 1 karakter spesial';
  }
  return null;
}

String? validatePasswordConfirmation(String password, String confirmation) {
  if (confirmation.isEmpty) return 'Konfirmasi kata sandi wajib diisi';
  if (confirmation != password) return 'Kata sandi tidak cocok';
  return null;
}

/// Turns a raw error from ApiClient.login/register into an Indonesian
/// message safe to show in the UI.
///
/// `AuthException.message` is whatever the gateway's `detail` field held:
/// a plain string for the known auth errors mapped below, but FastAPI's
/// pydantic validation errors put a list of error objects there instead
/// (not meant for end users) -- the fallback branch catches that shape
/// too instead of surfacing raw English/JSON.
String friendlyAuthError(Object error) {
  if (error is AuthException) {
    const knownMessages = {
      'Phone number already registered': 'Nomor telepon sudah terdaftar',
      'Invalid phone number or password': 'Nomor telepon atau kata sandi salah',
      'Account suspended': 'Akun Anda ditangguhkan',
    };
    for (final entry in knownMessages.entries) {
      if (error.message.contains(entry.key)) return entry.value;
    }
    return 'Terjadi kesalahan. Silakan coba lagi.';
  }
  return 'Tidak dapat terhubung ke server. Periksa koneksi internet Anda.';
}
