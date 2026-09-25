# EXAMPRO - Multi-Platform CBT Exam Browser

## Deskripsi Aplikasi
EXAMPRO merupakan solusi aplikasi peramban ujian berbasis komputer (Computer Based Test / CBT) multi-platform yang dirancang khusus untuk menjamin integritas, keamanan, dan kelancaran pelaksanaan asesmen pendidikan pada jenjang sekolah maupun perguruan tinggi. Aplikasi ini mengunci perangkat peserta secara ketat baik pada platform Android maupun Windows Desktop guna mencegah segala bentuk kecurangan digital, seperti membuka jendela aplikasi lain, mengambil tangkapan layar, maupun mengakses internet di luar server ujian. Dibangun dengan performa tinggi dan konsumsi daya yang efisien, EXAMPRO memberikan pengalaman navigasi ujian yang stabil, responsif, dan mudah dikelola oleh pihak penyelenggara ujian.

## Fitur Lengkap Aplikasi

### 1. Keamanan dan Proteksi Kiosk Mode
* **Native Keyboard & Shortcut Hook (Windows)**: Memblokir total kombinasi tombol sistem seperti Alt+Tab, Alt+Esc, tombol Windows, Ctrl+Esc, Ctrl+Shift+Esc, dan Task Manager agar peserta tidak dapat berpindah aplikasi.
* **Lock Task Mode & Device Admin (Android)**: Mengunci navigasi sistem Android, tombol Home, Recent Apps, dan status bar notifikasi selama sesi ujian berlangsung.
* **Proteksi Anti-Screenshot & Screen Recording**: Mencegah perekaman layar, mirroring, dan tangkapan layar secara menyeluruh di tingkat sistem operasi.
* **Auto Screen Brightness Control**: Mengatur dan mengunci tingkat kecerahan layar perangkat secara otomatis demi kenyamanan serta fokus peserta ujian.
* **Strict Fullscreen Lockdown**: Menampilkan antarmuka peramban satu layar penuh tanpa bilah navigasi atau kontrol browser standar.

### 2. Audio Peringatan dan Proteksi Suara
* **Alarm Pelanggaran Otomatis**: Memutar suara alarm peringatan kustom (.mp3) ketika peserta terdeteksi mencoba meminimalkan jendela atau melakukan pelanggaran.
* **Pengaturan Volume Fleksibel**: Mendukung penyesuaian volume suara peringatan dari 10% hingga 100% sesuai kebijakan sekolah.
* **Volume Lock Protection**: Mencegah penonaktifan suara atau penurunan volume oleh peserta melalui tombol fisik saat sistem alarm diaktifkan.

### 3. Navigasi dan Integrasi Server CBT
* **Penyematan URL Otomatis**: Membuka alamat server CBT sekolah secara instan begitu aplikasi dijalankan tanpa perlu mengetikkan URL manual.
* **Custom User-Agent Header**: Menyediakan header identitas peramban khusus untuk validasi keaslian akses di sisi script server CBT.
* **Pemindai QR Code CBT**: Memudahkan siswa membuka URL server ujian dengan memindai kode QR secara cepat.
* **Dialog Keluar Ber-PIN Rahasia**: Sesi aplikasi hanya dapat ditutup menggunakan kode PIN atau password khusus yang dipegang oleh pengawas ujian.

### 4. Kompatibilitas Multi-Platform & Otomatisasi Cloud Build
* **Dukungan Platform Ganda**: Menghasilkan installer Android (.APK) dan aplikasi portabel Windows (.EXE) siap pakai.
* **Split ABI Android Architecture**: Mendukung arsitektur arm64-v8a dan armeabi-v7a untuk kompatibilitas perangkat baru maupun lama.
* **Kompilasi Cloud Tanpa Beban Lokal**: Didukung workflow GitHub Actions untuk proses perakitan instan di cloud tanpa memerlukan instalasi SDK di perangkat lokal.
* **Visual Branding Kustom**: Mendukung penggantian logo ikon launcher aplikasi (.png / .jpg) dan identitas nama sekolah secara otomatis.