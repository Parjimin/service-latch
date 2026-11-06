# Lab PoC-1A — satu Windows 11 Stock x64

## Persiapan minimum

1. Gunakan hypervisor yang sudah tersedia dan **ISO resmi Windows 11 x64** dari [Microsoft](https://www.microsoft.com/software-download/windows11). Pilih **Home atau Pro** lebih dahulu, gunakan hak penggunaan yang sesuai. Tidak perlu menguji keduanya sebelum smoke pertama.
2. Buat VM dengan konfigurasi standar yang memenuhi Windows 11 (misalnya 2 vCPU, RAM 4 GiB, virtual disk 64 GiB, UEFI/Secure Boot dan TPM virtual yang didukung hypervisor). Tidak memakai Playbook, debloater atau bypass persyaratan sebagai baseline Stock.
3. Selesaikan setup Windows, siapkan akun berpassword dengan **autologin tidak aktif**. Catat edisi, full build dan x64. Ambil checkpoint baseline dan simpan export/clone independen untuk memulihkan lab; pastikan dapat dipakai sebelum mutasi. Tidak diperlukan inventaris panjang perangkat host.
4. Salin artifact build/source. Jika build dilakukan di CI, VM tidak perlu Rust/Visual Studio. Catat hash binary; tinjau skrip. Buka admin PowerShell hanya ketika instalasi/Start/Stop/uninstall telah disetujui. Jangan mengubah ExecutionPolicy mesin; jika kebijakan organisasi menolak skrip, laporkan BLOCKED.

Tidak perlu mengubah service Windows, power settings, ACL OS, audit policy, network adapter atau Event Log untuk pengujian ini. Service PoC tidak membutuhkan Internet. Tidak mengubah lingkungan ReviOS utama menjadi Stock.

## Smoke tanpa reboot

Setelah instalasi yang disetujui, jalankan `Test-Smoke.ps1 -LabConfirmed`. Ia menguji manual Start/Stop serta dua fault mode sementara, dan meninggalkan service Stopped. Simpan keluaran, `Get-LabStatus.ps1`, log dan hash sebelum cleanup. PASS smoke **tidak** sama dengan PASS Automatic boot.

Untuk pengukuran, jalankan Start normal dari Services.msc atau `sc.exe start ServiceLatch.Poc1A.8f61bc537e1c49aaa52ae744ad486ef0` setelah disetujui, lalu:

```powershell
.\scripts\Measure-Idle.ps1 -Seconds 600
```

Ini query read-only selama sepuluh menit. Jangan memakai sesi tool interaktif yang harus tetap responsif untuk menunggu skrip ini; operator dapat menjalankannya di PowerShell lab. Ia memeriksa PID/start time tetap sama dan memberi rata-rata CPU terhadap total logical CPU, RAM dan delta process I/O. CPU timer tidak diukur pada satu snapshot. Process I/O bukan physical disk I/O dan tidak mengukur trafik jaringan. Ulangi jika process berubah, VM tersuspensi, atau hasil tidak sah.

## Bukti Automatic dan tanpa login

Uji ini baru dilakukan ketika operator menyetujui restart/boot guest; paket tidak menjalankannya otomatis.

1. Pastikan konfigurasi **Auto, LocalService, Own Process**, command line normal tanpa fault flags; simpan hash dan run ID log terakhir. Selesaikan pekerjaan di guest.
2. Catat waktu UTC host dan guest serta selisih jamnya. Pastikan tidak ada sesi autologin. Mulai restart guest **secara manual**.
3. Saat layar sign-in guest muncul, **jangan login setidaknya 60 detik**. Operator mencatat waktu host saat layar terlihat dan tepat sebelum memasukkan kredensial; catat bahwa tidak ada login/remote login/autologin selama interval tersebut.
4. Login, segera ambil `Get-LabStatus.ps1` dan salin log. Cocokkan run ID/PID baru, `StartTimeUtc`, event `running` dan status Running/SessionId 0. Periksa kembali selisih jam host/guest. Waktu mulai/running harus mendahului login yang dicatat dengan margin yang melebihi ketidakpastian jam.
5. Jika jam berubah/tidak dapat direkonsiliasi, autologin terjadi, operator tidak yakin, atau bukti tertimpa: tandai **INCONCLUSIVE**, bukan PASS. SessionId 0 atau service Running setelah login saja **tidak membuktikan** ia sudah berjalan sebelum login. Laporkan sumber bukti sebagai pengamatan operator + log worker/SCM, dengan batas tersebut.
6. Periksa status tetap Running tanpa membuka aplikasi UI apa pun. Tidak ada UI/IPC dalam PoC ini; tidak mengklaim uji menutup UI produk yang belum dibuat.

Tidak ada pembacaan massal event lifecycle, classifier, atau perubahan auditing untuk membuktikan ini. Build pada Home dan Pro dilaporkan terpisah. Satu boot yang berhasil adalah satu observasi, bukan jaminan stabilitas statistik semua Windows.

## Shutdown normal dan cleanup

Penanganan `SERVICE_CONTROL_SHUTDOWN` tersedia, tetapi PASS Stop manual tidak membuktikan jalur shutdown OS. Jika operator menyetujui pengujian shutdown guest, simpan pekerjaan dan lakukan manual, lalu pada penggunaan berikutnya cari event `shutdown_requested` dari run sebelumnya. Tidak adanya log pada shutdown abrupt tidak menjamin callback gagal atau sukses; laporkan apa yang teramati. Tidak perlu sengaja mematikan paksa atau membuat BSOD.

Simpan bukti di luar dua direktori instalasi sebelum `Uninstall-Lab.ps1`. Konfirmasikan service absent, kedua root absent dan tidak ada proses binary PoC yang tertinggal. Jika status masih marked-for-delete, tutup Services.msc/handle terkait dan ulangi. Jangan menghapus file sebelum registrasi benar-benar hilang. Jika ada dependents/ownership mismatch/reparse point, berhenti dan tinjau; baseline VM yang disimpan adalah rollback terakhir.

Log/hasil dapat memuat waktu penggunaan, nama VM, edisi/build dan path akun. Tinjau sebelum berbagi atau commit; workflow tidak mengunggah log pribadi dari laptop.
