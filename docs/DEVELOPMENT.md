# Backend-first — keputusan 6 November 2026

Prioritas aktif hanya **Windows Build Verification dan runtime PoC-1A**. Kode source, cross-check dan CI tidak otomatis meluluskan service startup sebelum login di Windows 11 Stock.

| Tahap | Cakupan | Gate |
|---|---|---|
| PoC-1A — aktif | Build/link Windows x64; Automatic SCM; LocalService; Start/Stop; kegagalan startup/cleanup; log/idle; uninstall | Bukti runtime Stock sesuai acceptance criteria PoC-1A; gap dilaporkan, tidak dianggap PASS |
| PoC-1B — belum dimulai | Service dummy milik eksperimen; snapshot; Stop/Disable; Restore | PoC-1A tervalidasi pada cakupan yang dipakai, lalu acceptance criteria khusus PoC-1B |
| PoC-1C — belum dimulai | Crash recovery; watchdog; privilege; IPC; rollback | Hasil PoC-1B dan pengaman dasar tersedia sebelum mutasi; validasi fault/security terpisah |
| Backend MVP | Menggunakan hasil PoC yang sudah tervalidasi | Tidak mengangkat asumsi PoC menjadi janji produk |
| Kontrak IPC/data | Mendefinisikan kontrak berdasarkan backend yang terbukti | Versi dan otorisasi operasi jelas sebelum integrasi UI |
| UI produksi | Integrasi dengan backend inti yang stabil | Framework belum dipilih; tidak menjadi dependency worker |

Prototype UI dapat dirancang sebelum seluruh backend selesai, sebagai jalur terpisah HTML/CSS/JavaScript dengan **mock data saja**. Prototype tidak terhubung ke SCM/Windows Service, tidak mengubah sistem, dan bukan bukti pengujian backend. Permintaan prototype bukan izin memperluas PoC-1A. Pada tahap saat ini belum ada kode UI yang ditambahkan.

Backend kelak harus dapat menyampaikan: status worker; status setiap target dan keadaan yang diinginkan/teramati; identitas/revisi operasi; progres; hasil verifikasi; kegagalan parsial dan kode error; serta status recovery. Ini daftar kebutuhan antarmuka, **bukan kontrak IPC final atau implementasi PoC-1B/C**. Menutup UI tidak menjadi pemicu penghentian worker.

CI tetap GitHub Actions. Windows 11 Home/Pro Stock adalah baseline; ReviOS target tambahan. Hasil runner Windows Server, VM Stock, perangkat fisik, simulasi dan ReviOS dicatat terpisah. Instalasi, Start/Stop, cleanup dan boot lab memerlukan persetujuan yang sesuai; pipeline build tidak melakukannya.

Classifier lifecycle satu boot tetap dicabut. Tidak ada audit ulang event shutdown/sleep, pemilihan framework UI, Default/Custom atau backend produksi di perubahan ini.
