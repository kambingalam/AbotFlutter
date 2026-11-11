# Kontrak rute app ↔ firmware (target V3.47)

Berlaku untuk pesan `route`. Sisi app sudah diimplementasikan; firmware perlu
menyesuaikan tiga hal di bawah.

## 1. Bentuk pesan dari app

```json
{"t":"route","dist":12401,"dur":1832,"coords":[[98.6,3.5],...],"steps":[{"instr":"BELOK KIRI","road":"Jl. Sudirman","dist":123.5,"idx":12,"routeDist":987.7,"imp":true}]}
```

- `coords` maksimal 120 titik, tiap angka dibulatkan 5 desimal (~1 m).
- `road` hanya ASCII, maksimal 20 karakter.
- `dist`/`dur`/`dist` langkah dibulatkan ke satuan/0,1.
- Payload dijaga di bawah 8000 byte. Kalau masih lebih, app membuang langkah
  dengan `imp:false`, lalu menurunkan jumlah titik (120 → 60 → 30).

## 2. Firmware wajib membalas ack/nack

Setelah `route` diterima dan disimpan:

```json
{"t":"ack","for":"route"}
```

Kalau ditolak (payload > `LINK_LINE_MAX`, `coords` < 2, heap kurang):

```json
{"t":"nack","for":"route","why":"too_big"}
```

Pesan di atas 8 KB sekarang dibuang tanpa kabar; ganti dengan `nack` supaya app
tahu harus mengirim ulang. App menunggu ack 3 detik, mengulang sekali, lalu
menyerahkan sisanya ke resync heartbeat.

## 3. Heartbeat harus jujur soal rute

```json
{"t":"hb","ver":"3.47","up":123,"heap":84200,"route":1,"trip":1}
```

- `route` = 1 jika tabel rute tersimpan dan tidak kosong, 0 jika tidak.
- `trip` = 1 jika trip sedang aktif.

App memakai dua field ini: saat `trip=1` dan `route=0`, app mengirim ulang rute
(maksimal sekali per 10 detik). Kalau `route` selalu 0 atau tidak dikirim,
resync tidak pernah jalan.

## Yang tidak berubah

- Firmware tetap hanya mencatat `offroute`; app yang memutuskan reroute.
- Format pesan lain (`auth`, `gps`, `trip_start`, `trip_end`, `ping`, `pong`,
  `arrived`, `ota_*`) tidak berubah.
