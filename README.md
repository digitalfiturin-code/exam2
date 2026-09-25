# EXAMPRO — Custom Exam Browser

Aplikasi browser ujian CBT (*Computer Based Test*) yang sangat aman dan mendukung multi-platform: **Android (APK)** dan **Windows (EXE)**.

---

## 🔒 Fitur Keamanan Premium

1. **Native Keyboard Hook (Windows)**: Memblokir total kombinasi tombol **Alt+Tab**, **Alt+Esc**, dan **Tombol Windows** di tingkat OS. Siswa tidak bisa berpindah aplikasi.
2. **Pencegahan Alarm Palsu (Windows)**: Deteksi blur dilewati ketika siswa mengeklik kotak teks untuk mengetik username/password di dalam WebView. Pengecekan minimize tetap aktif.
3. **Android Volume Lock**: Memblokir total tombol fisik volume (*up/down/mute*) dan mengunci volume sistem pada **40%**.
4. **Kecerahan Otomatis**: Layar otomatis disetel pada tingkat kecerahan yang ditentukan saat aplikasi aktif untuk memastikan kenyamanan siswa.
5. **Anti-Screenshot & Screen Recording**: Layar otomatis diamankan dari perekaman layar dan tangkapan layar.
6. **Split APK per ABI**: Build otomatis memisahkan APK untuk HP Android lama (`armeabi-v7a`) dan baru (`arm64-v8a`) demi menghemat ruang penyimpanan.

---

## ⚙️ Cara Mengubah Pengaturan Aplikasi

Semua konfigurasi penting berada di dalam file **`lib/main.dart`**. Buka file tersebut dan ubah nilai variabel sesuai kebutuhan:

### 1. Mengaktifkan / Menonaktifkan Suara Alarm Alert (Baris 67)
Tersedia tombol toggle konfigurasi di `lib/main.dart`:
```dart
// Ubah ke `false` untuk mematikan suara (Mode Senyap / Default)
// Ubah ke `true` untuk menyalakan suara alarm pelanggaran & dialog keluar
final bool enableAlertAudio = false;
```
> **💡 Catatan Penggunaan `alert.mp3`:**
> - **Jika Tidak Ingin Suara (Off):** Biarkan `enableAlertAudio = false`. File `assets/alert.mp3` tetap dibiarkan di foldernya agar tidak merusak build Flutter di GitHub Actions.
> - **Jika Ingin Suara Aktif (On):** Ubah menjadi `enableAlertAudio = true`. Saat siswa melanggar (misal Alt+Tab/Home) atau membuka menu keluar, suara `alert.mp3` akan berbunyi otomatis.
> - **Jika Ingin Mengganti Suara:** Cukup ganti file `assets/alert.mp3` dengan audio MP3 pilihan Anda (tetap gunakan nama file `alert.mp3`).
> - **PERINGATAN PENTING:** Jangan menghapus file fisik `assets/alert.mp3` tanpa menghapus deklarasinya di `pubspec.yaml`. Jika file fisik dihapus tapi masih terdaftar di `pubspec.yaml`, proses compile build di GitHub Actions akan **ERROR**. Cara paling aman adalah cukup atur `enableAlertAudio = false`.

---

### 2. Mengubah Password Keluar (Baris 61)
Cari kode berikut dan ubah dengan password yang Anda inginkan:
```dart
final String exitPassword = "085086";
```

### 3. Mengubah Nama Sekolah (Baris 62)
Cari kode berikut dan ubah dengan nama sekolah Anda:
```dart
final String schoolName = "SMPN 4 DEPOK";
```

### 4. Mengubah Link Ujian (Baris 122 & Baris 73)
- **Baris 122 (URL Utama Saat Aplikasi Dibuka - Paling Penting):**
  Cari fungsi `_checkSavedUrl()` dan ubah link ujian di dalam tanda kutip:
  ```dart
  currentUrl = "https://sites.google.com/guru.smp.belajar.id/asesmenpasmer/home";
  ```
- **Baris 73 (Default Variabel Inisialisasi):**
  Samakan juga URL pada deklarasi variabel awal:
  ```dart
  String currentUrl = "https://sites.google.com/guru.smp.belajar.id/asesmenpasmer/home";
  ```

### 5. Mengubah Kecerahan Otomatis (Baris 214)
Cari kode berikut dan ganti angka `0.4` (40%) dengan nilai kecerahan yang diinginkan (antara `0.0` hingga `1.0`):
```dart
await ScreenBrightness.instance.setScreenBrightness(0.4);
```

### 6. Mengubah Kunci Volume Sistem Android (Di File `build_apk.yml` Baris 85)
Buka file `.github/workflows/build_apk.yml`, cari kode berikut, lalu ubah desimal `0.4` (40%) dengan tingkat volume yang diinginkan (misal `0.5` untuk 50%):
```kotlin
val targetVolume = (maxVolume * 0.4).toInt()
```

---

## 🖼️ Cara Mengganti Logo Aplikasi

1. Siapkan file logo sekolah Anda dalam format **PNG** dengan nama **`logo.png`**.
2. Simpan/tumpuk file logo baru tersebut di folder proyek pada direktori:
   ```text
   assets/logo.png
   ```
3. Sistem build GitHub Actions akan otomatis mendeteksi logo tersebut dan meregenerasi ikon aplikasi untuk versi Android maupun Windows EXE secara otomatis saat dicompile.

---

## 🚀 Cara Melakukan Build Otomatis via GitHub Actions

Setelah melakukan perubahan kode di komputer lokal, ikuti langkah berikut untuk mengirim perubahan ke GitHub dan memulai build otomatis:

### Langkah 1: Push Perubahan ke GitHub
Buka terminal (PowerShell / Git Bash / Command Prompt) di folder proyek Anda, lalu jalankan:

```powershell
git add .
git commit -m "update: nonaktifkan audio alert dan perbarui konfigurasi"
git push origin main
```

### Langkah 2: Mengunduh Hasil Aplikasi
1. Buka halaman repositori **GitHub** Anda di web browser.
2. Masuk ke menu/tab **Actions** di bagian atas.
3. Anda akan melihat alur kerja (workflow) sedang berjalan (ditandai dengan lingkaran kuning berputar). Tunggu sekitar 4-5 menit hingga selesai (lingkaran berubah hijau).
4. Klik pada nama commit terbaru Anda.
5. Gulir ke bagian paling bawah (**Artifacts**). Anda dapat mengunduh berkas installer:
   * **`EXAMPRO-APK`**: Berisi file APK terpisah untuk HP Android baru dan lama.
   * **`EXAMPRO-Windows-EXE`**: Berisi berkas ZIP aplikasi Windows (tinggal diekstrak dan jalankan `EXAMPRO.exe`).