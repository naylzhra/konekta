import '../../core/api/api_client.dart';

String? validatePhoneNumber(String value) {
  if (value.isEmpty) return 'Nomor telepon wajib diisi';
  if (value.length < 10 || value.length > 12) {
    return 'Nomor telepon tidak valid';
  }
  return null;
}

final _hasDigit = RegExp(r'[0-9]');
final _hasSpecialChar = RegExp(r'[^A-Za-z0-9]');

// Password policy: minimum 8 characters, at least 1 digit, at least 1 special (non-alphanumeric) character.
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
