# Service Latch PoC-1A — Minimal Windows Service

Eksperimen Rust **no-op**, bukan aplikasi produksi. Satu Windows Service Automatic, akun **NT AUTHORITY\LocalService**, tanpa UI, target service, IPC, database, watchdog, registry fallback, scheduled task, atau Startup Apps. ADR v1.4 tetap berlaku; PoC-0 lifecycle tetap ditutup.

Strategi proyek adalah **Backend-First**, dengan prototype UI HTML/CSS/JavaScript terpisah menggunakan mock data. Fokus aktif tetap Windows Build Verification dan runtime PoC-1A; belum memilih framework UI produksi. Lihat [batas tahap development](docs/DEVELOPMENT.md).

**Status saat penyerahan:** lihat [docs/VALIDATION.md](docs/VALIDATION.md). Unit test dan pemeriksaan kode tidak membuktikan auto-start di Windows 11 Stock. Tidak ada instalasi/reboot/perubahan Windows yang dijalankan oleh pembuat paket ini.

## Isi proyek

| Path | Isi |
|---|---|
| `Cargo.toml`, `Cargo.lock`, `rust-toolchain.toml` | Rust 1.90.0; satu dependency langsung Windows `windows-service = 0.8.1`, versi tepat; seluruh transitive dependency dikunci |
| `src/windows.rs` | Dispatcher SCM, handler Stop/Shutdown, status pending/running/stopped, penanganan error/panic |
| `src/log.rs`, `src/lib.rs` | Log terbatas dan parsing argumen uji, beserta unit test |
| `scripts/Native.cs`, `scripts/Common.ps1` | API instalasi SCM dan pengaman identitas/path/ACL |
| `scripts/Install-Lab.ps1`, `Uninstall-Lab.ps1` | Instalasi transactional dan penghapusan instalasi milik eksperimen |
| `scripts/Test-Smoke.ps1` | Start/Stop normal serta kegagalan startup/cleanup terkendali |
| `scripts/Get-LabStatus.ps1`, `Measure-Idle.ps1` | Observasi terarah dan pengukuran idle |
| `tests/ScriptChecks.ps1` | Parser PowerShell, kompilasi deklarasi C#, fixture penolakan ownership dan reparse point |
| `.github/workflows/windows.yml` | Windows x64 build, fmt, Clippy, unit test dan artifact; tidak memasang service |
| `docs/LAB.md`, `ACCEPTANCE.md`, `results-template.json` | Prosedur VM, bukti boot/no-login, cleanup dan format hasil |

## Build Windows x64 — tanpa hak admin

Gunakan Windows x64, Rustup, serta **Visual Studio Build Tools 2022** dengan workload **Desktop development with C++** dan Windows SDK. Menyediakan toolchain/build tools merupakan tindakan persiapan yang dipilih pengguna; proyek tidak memasangnya diam-diam. Buka PowerShell biasa di root proyek:

```powershell
rustup toolchain install 1.90.0 --profile minimal --component rustfmt --component clippy --target x86_64-pc-windows-msvc
cargo fmt --all -- --check
cargo clippy --locked --all-targets --target x86_64-pc-windows-msvc -- -D warnings
cargo test --locked --all-targets --target x86_64-pc-windows-msvc
.\tests\ScriptChecks.ps1
cargo build --locked --release --target x86_64-pc-windows-msvc
Get-FileHash .\target\x86_64-pc-windows-msvc\release\service-latch-poc1a.exe -Algorithm SHA256
```

`cargo test` tidak mendaftarkan service atau memanggil SCM. `ScriptChecks.ps1` hanya mengompilasi deklarasi native serta menggunakan fixture/file sementara; tidak memanggil API perubahan service. Cargo.lock harus disertakan dan build menggunakan `--locked`. Jangan memperbarui dependency saat sedang mengulang pengukuran yang sama.

## Tinjau dahulu, lalu instal hanya di lab yang disetujui

Sediakan **satu VM Windows 11 Home atau Pro Stock x64**; tidak perlu memasang PoC pada laptop ReviOS. Lihat [prosedur singkat lab](docs/LAB.md). Installer tidak melakukan elevasi sendiri. `-LabConfirmed` merupakan pernyataan operator bahwa ini VM lab, bukan deteksi otomatis VM.

Rencana read-only (PowerShell Windows x64; tidak perlu admin):

```powershell
.\scripts\Install-Lab.ps1 -BinaryPath .\target\x86_64-pc-windows-msvc\release\service-latch-poc1a.exe -WhatIf
```

**Langkah berikut hanya setelah pengguna menyetujui instalasi di VM.** Buka PowerShell x64 sebagai Administrator di VM tersebut:

```powershell
.\scripts\Install-Lab.ps1 -BinaryPath .\target\x86_64-pc-windows-msvc\release\service-latch-poc1a.exe -LabConfirmed
.\scripts\Get-LabStatus.ps1
.\scripts\Test-Smoke.ps1 -LabConfirmed
```

Setiap skrip mutasi menampilkan konfirmasi. Installer membuat service Automatic **dalam keadaan Stopped**; tidak langsung menjalankannya dan tidak me-reboot. Smoke test adalah persetujuan terpisah untuk Start/Stop dan fault mode. Smoke test meninggalkan service Stopped; saat boot lab berikutnya, SCM akan mencoba auto-start normal. Tidak ada reboot command dalam paket ini.

Jika menggunakan artifact CI, binary berada di root artifact: ganti `-BinaryPath` menjadi `.\service-latch-poc1a.exe`. Skrip dan dokumen berada di folder yang sama seperti paket source. Jangan menjalankan executable service langsung untuk membuktikan startup: tanpa SCM ia mengembalikan error. `--version` hanya menampilkan versi.

## Identitas dan batas mutasi

Nama tetap unik untuk PoC ini:

```text
ServiceLatch.Poc1A.8f61bc537e1c49aaa52ae744ad486ef0
```

Lokasi instalasi memakai folder sistem yang dibaca dari Windows:

- `%ProgramFiles%\ServiceLatch-Poc1A-8f61bc537e1c49aaa52ae744ad486ef0` — binary, admin/SYSTEM write; LocalService read/execute.
- `%ProgramData%\ServiceLatch-Poc1A-8f61bc537e1c49aaa52ae744ad486ef0` — marker ownership read-only untuk worker; subfolder `logs` dapat ditulis oleh LocalService dan admin/SYSTEM.

Nama/folder yang sudah ada menyebabkan **penolakan**, bukan diadopsi/ditimpa. Folder dibuat dengan DACL terlindungi sejak penciptaannya. Marker memuat ID proyek, path persis dan hash binary. Uninstall memeriksa marker, konfigurasi service, hash serta reparse point sebelum stop/delete. Marker adalah catatan kepemilikan di lokasi admin-protected, bukan tanda tangan digital atau perlindungan terhadap admin yang bermusuhan.

SCM menjalankan service sebagai **LocalService** (SID bawaan S-1-5-19), dengan daftar privilege minimum `SeChangeNotifyPrivilege`. Tidak ada perubahan ACL/service Windows lain, pembuatan akun, network credential, atau fallback jika izin ditolak. Ketika konfigurasi berubah di luar skrip ini, tindakan otomatis ditolak dan operator meninjau kondisi lab.

LocalService adalah akun bersama: proses LocalService lain juga memiliki izin ke log ini. Untuk eksperimen no-op ini log tidak pernah dibaca sebagai konfigurasi/otorisasi dan bukti diasumsikan berasal dari lab yang tidak dimanipulasi. Isolasi identitas per-service untuk produk belum dibuktikan dan tidak diklaim oleh PoC-1A. ACL binary dan marker tetap tidak memberikan write kepada LocalService.

## Perilaku worker

Status normal: `START_PENDING → RUNNING → STOP_PENDING → STOPPED`. Handler hanya mengirim sinyal melalui channel kapasitas satu; tidak melakukan file I/O. Thread worker **memblokir pada receiver**, tanpa busy polling/timer/heartbeat. Stop dan Shutdown menutup log, melaporkan status terakhir, lalu keluar. Tidak ada preshutdown delay, reboot request, atau proses anak.

Mode kegagalan uji hanya berlaku untuk satu `StartService`:

| Mode | Hasil yang diharapkan |
|---|---|
| Normal | Running; sesudah Stop, Win32 exit 0 |
| `--fail-startup` | Tidak Running; Stopped dengan Win32 1066 / service-specific 1001 |
| `--fail-cleanup` | Running; setelah Stop, Stopped dengan Win32 1066 / service-specific 1002 |
| Argumen SCM tidak dikenal | Stopped dengan Win32 87 |
| Log tidak dapat dibuka/ditulis | Berhenti dengan kode error I/O; startup tidak diklaim berhasil |
| Panic Rust yang tertangkap di boundary worker | Stopped dengan service-specific 1003; bukan jaminan tahan abort/OOM/kill |

Recovery action otomatis **tidak dikonfigurasi** pada PoC-1A; fault test tidak memicu restart/reboot. Pengujian crash dan recovery produk berada di PoC lain dan tidak dibuat di sini.

Log berisi timestamp Unix UTC, elapsed monotonic proses, run ID/PID, event dan kode. Timestamp hanya bukti observasi, bukan classifier boot. Hanya boundary aktivitas yang ditulis dan disinkronkan; idle tidak menulis. Maksimum dua file masing-masing 256 KiB (`events.log`, `events.previous.log`). Simpan bukti sebelum uninstall/rotasi. Log `cleanup_complete` menunjukkan cleanup worker selesai; status Stopped harus tetap diverifikasi lewat SCM.

## Penghapusan dan rollback

Setelah bukti disalin ke folder hasil pilihan pengguna, pratinjau dan konfirmasikan penghapusan di VM:

```powershell
.\scripts\Uninstall-Lab.ps1 -WhatIf
.\scripts\Uninstall-Lab.ps1 -LabConfirmed
.\scripts\Get-LabStatus.ps1
```

Uninstaller mengirim Stop hanya ke service PoC, menunggu maksimal 20 detik, menghapus registrasi melalui `DeleteService`, memastikan service benar-benar hilang, lalu menghapus dua folder milik eksperimen **termasuk log**. Tidak menghentikan dependents, force-kill, atau menghapus registry langsung. Handle dari Services.msc dapat menunda penghapusan; skrip melaporkan ini dan mempertahankan file. Tutup handle/UI Services, kemudian ulangi pemeriksaan dan uninstall. Jika ownership/fingerprint berbeda, jangan memaksa: simpan bukti dan pulihkan VM lab dari baseline yang sudah disiapkan.

Installer yang gagal hanya mencoba rollback objek yang berhasil dibuat oleh invocation itu. Jika penghapusan service belum dapat dipastikan, file dan marker dipertahankan untuk recovery yang ditinjau. Checkpoint/export VM merupakan fallback lab, bukan implementasi snapshot/rollback target produk PoC-1B/C.

## Izin dan pengujian

| Kegiatan | Aman otomatis dalam lingkup ini | Perlu persetujuan/otoritas |
|---|---|---|
| Build, fmt, Clippy, unit test, parser/fixture script | Ya; akun biasa/CI, hanya source/build/temp files | Tidak memerlukan admin |
| Pratinjau `-WhatIf`, query status/pengukuran yang diizinkan akun | Ya; tanpa perubahan service | Tidak melakukan elevasi jika ditolak |
| Instalasi, Start/Stop/fault smoke, penghapusan | Tidak dijalankan oleh CI | Persetujuan eksplisit pengguna untuk VM lab; PowerShell admin; konfirmasi skrip |
| Boot/restart/power-off VM untuk validasi | Tidak ada otomatisasi dalam paket | Persetujuan operator per pengujian; lakukan manual di VM |
| Instalasi pada Windows utama ReviOS | Bukan prasyarat dan tidak dilakukan | Di luar pelaksanaan ini |

Langkah berikutnya adalah menjalankan **build CI atau build Windows**, kemudian instalasi lab yang disetujui. [Acceptance criteria](docs/ACCEPTANCE.md) dan [template hasil](docs/results-template.json) membedakan source checks, runner Windows Server, VM Stock dan ReviOS. Jangan mengisi PASS untuk kasus yang belum dijalankan.

## Referensi implementasi

- [Microsoft: ServiceMain](https://learn.microsoft.com/en-us/windows/win32/services/service-servicemain-function)
- [Microsoft: Service State Transitions](https://learn.microsoft.com/en-us/windows/win32/services/service-status-transitions)
- [Microsoft: LocalService](https://learn.microsoft.com/en-us/windows/win32/services/localservice-account)
- [Microsoft: CreateServiceW](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-createservicew)
- [Microsoft: ChangeServiceConfig2W](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-changeserviceconfig2w)
- [Microsoft: DeleteService](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-deleteservice)
- [windows-service 0.8.1, dokumentasi pembuat wrapper](https://docs.rs/windows-service/0.8.1/windows_service/)

Paket belum dipublikasikan ke repository atau sebagai rilis. Pilihan lisensi proyek publik belum dibekukan dalam eksperimen ini; lisensi dependency tercantum pada metadata crate masing-masing.
