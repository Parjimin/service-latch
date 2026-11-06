# Service Latch

Eksperimen aplikasi Windows untuk pengendalian service yang terarah.

Strategi pengembangan: **Backend-First**, dengan prototype UI HTML/CSS/JavaScript sebagai jalur terpisah menggunakan mock data. Framework dan UI produksi belum dipilih.

Urutan: PoC-1A runtime Windows → PoC-1B dummy/snapshot/Stop-Disable/Restore → PoC-1C recovery/watchdog/privilege/IPC/rollback → backend MVP → kontrak IPC/data yang stabil → integrasi UI produksi.

Fokus aktif: **Windows Build Verification dan validasi PoC-1A**. Home/Pro Stock merupakan baseline; ReviOS target kompatibilitas tambahan. CI Windows tidak membuktikan auto-start sebelum login pada Windows 11 Stock.

Kode eksperimen dan hasil CI disiapkan di branch PoC. Belum ada klaim produk siap dipakai atau pengujian Windows runtime lulus.
