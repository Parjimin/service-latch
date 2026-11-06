# Acceptance criteria PoC-1A

Status: PASS / FAIL / INCONCLUSIVE / BLOCKED / NOT RUN / NOT APPLICABLE. Record hasil selalu memuat versi/hash source dan binary, full build, edisi, architecture OS/proses, Stock/ReviOS, fisik/VM/runner, akun, tindakan operator dan bukti. Tidak mewarisi PASS maupun target pengulangan PoC-0 yang dicabut.

| ID | Bukti penerimaan | Lingkungan yang tepat |
|---|---|---|
| A-01 | Source lengkap, Cargo.lock, toolchain/dependency tepat; fmt/Clippy/unit test/build release Windows x64 sukses | CI/build Windows; cross-check saja dilabeli cross-check |
| A-02 | Instalasi menghasilkan tepat satu service Auto, Own Process, LocalService, privilege minimum dan ACL milik eksperimen; tidak menimpa collision | VM Stock, admin dan persetujuan |
| A-03 | Start normal Running; Stop normal Stopped dan Win32 0; start lagi sukses; pending/control handler tidak hang | VM Stock smoke |
| A-04 | Fault startup: Stopped 1066/1001 tanpa Running; fault cleanup: Stopped 1066/1002; start berikutnya normal tanpa konfigurasi ulang | VM Stock smoke |
| A-05 | Start otomatis tanpa login dengan pengamatan operator + bukti baru yang mendahului login; tidak hanya SessionId 0 setelah login | Boot VM Stock yang disetujui |
| A-06 | Tidak ada proses UI, pengguna tidak perlu membuka aplikasi, worker tetap Running | VM Stock; uji UI-close produk NOT APPLICABLE |
| A-07 | Boundary log cukup; idle tidak menambah heartbeat/log; rotasi maksimal 2 x 256 KiB; error log startup tidak dilaporkan sukses | Unit fixture + VM; kondisi log gagal dapat diuji di lab nanti |
| A-08 | CPU/RAM/I/O diukur saat idle; kandidat rata-rata CPU <=0,1% total mesin selama 600 detik dan private bytes <=40 MiB; delta write idle diharapkan 0 | VM Stock setelah startup stabil; angka belum klaim hasil |
| A-09 | Uninstall hanya service/folder PoC; menunggu stop/deletion, menolak foreign ownership/reparse/dependents; rerun setelah absent aman | Fixture guard + VM Stock cleanup |
| A-10 | Tidak ada service lain yang diubah, launcher cadangan, watchdog, database, IPC atau registry fallback | Review source + catatan perubahan lab |
| A-11 | SERVICE_CONTROL_SHUTDOWN normal ditangani tertib; tidak menahan shutdown dengan preshutdown; bukti callback run sebelumnya disimpan | Shutdown guest yang disetujui; terpisah dari manual Stop |

Target startup <1 detik dan dampak boot kecil adalah sasaran eksperimen, bukan jaminan. Laporkan waktu aktual dan kondisi host; bandingkan boot lab yang sama dengan/tanpa service ketika perlu menilai dampak. SCManager Running cepat saja bukan bukti seluruh boot tidak terdampak. Tidak mengklaim stabilitas atau kompatibilitas publik dari satu percobaan.

Pengujian unit/fixture di Linux tidak dihitung sebagai A-02–A-06/A-08/A-09 aktual/A-11. CI windows-2022 memakai runner Windows Server dan tidak me-reboot; CI hijau tidak meluluskan Automatic/no-login Windows 11 Home/Pro.
