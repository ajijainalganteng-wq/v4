#!/bin/bash
# install_dropbear2019.sh — Instal Dropbear 2026.94 LANGSUNG dari source.
# Dipanggil otomatis oleh setup-main.sh (ins_dropbear) di setiap setup baru.
#
# Menggunakan Dropbear upstream terbaru, dengan kompatibilitas algoritma
# SSH lama yang masih tersedia pada versi terbaru.
#
# Pola sama seperti script sebelumnya:
# paket apt tetap terinstal untuk unit systemd-nya;
# yang diganti hanya binary di /usr/sbin.

set -e

VERSION="2026.94"
URL="https://matt.ucc.asn.au/dropbear/releases/dropbear-${VERSION}.tar.bz2"

echo "[install_dropbear] Instalasi dependensi build..."
apt-get update -y || true
apt-get install -y build-essential zlib1g-dev libtomcrypt-dev libtommath-dev wget bzip2
apt-get install -y libcrypt-dev 2>/dev/null || apt-get install -y libxcrypt-dev 2>/dev/null || true

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cd "$TMPDIR"

echo "[install_dropbear] Download source Dropbear ${VERSION} (3x percobaan)..."
DL_OK=0
for i in 1 2 3; do
    if wget --timeout=30 --tries=2 -q "$URL" -O dropbear.tar.bz2 && tar tjf dropbear.tar.bz2 >/dev/null 2>&1; then DL_OK=1; break; fi
    sleep 5
done
[ "$DL_OK" = 1 ] || { echo "[install_dropbear] Gagal unduh source Dropbear."; exit 1; }
tar xjf dropbear.tar.bz2
cd "dropbear-${VERSION}"

echo "[install_dropbear] Mengaktifkan kompatibilitas algoritma SSH lama..."

# Konfigurasi khusus menggunakan localoptions.h sesuai struktur upstream terbaru.
cat > localoptions.h <<'EOF'
#define DROPBEAR_ENABLE_CBC_MODE 1
#define DROPBEAR_ENABLE_CTR_MODE 1
#define DROPBEAR_3DES 1
#define DROPBEAR_SHA1_HMAC 1
#define DROPBEAR_SHA1_96_HMAC 1
#define DROPBEAR_DSS 1
#define DROPBEAR_RSA_SHA1 1
#define DROPBEAR_DH_GROUP1 1
#define DROPBEAR_DH_GROUP1_CLIENTONLY 0
#define DROPBEAR_DH_GROUP14_SHA1 1
#define DROPBEAR_USER_ALGO_LIST 1
EOF

echo "[install_dropbear] Build (2-5 menit)..."
if ! ./configure --prefix=/usr --sysconfdir=/etc --disable-pam >/dev/null 2>&1 \
    || ! make -j"$(nproc)" PROGRAMS="dropbear dropbearkey dropbearconvert" >/dev/null 2>&1; then
    echo "[install_dropbear] Build dengan lib sistem gagal, coba bundled libtom..."
    make distclean >/dev/null 2>&1 || true
    ./configure --prefix=/usr --sysconfdir=/etc --disable-pam --enable-bundled-libtom >/dev/null
    make -j"$(nproc)" PROGRAMS="dropbear dropbearkey dropbearconvert"
fi

echo "[install_dropbear] Install binary..."
install -m 755 dropbear /usr/sbin/dropbear
install -m 755 dropbearkey /usr/sbin/dropbearkey
install -m 755 dropbearconvert /usr/sbin/dropbearconvert

# Kunci host DSS wajib ada agar ssh-dss ditawarkan.
mkdir -p /etc/dropbear
[ ! -f /etc/dropbear/dropbear_dss_host_key ] && /usr/sbin/dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key

echo "[install_dropbear] Mencegah apt menimpa build khusus..."
apt-mark hold dropbear dropbear-bin >/dev/null 2>&1 || true

echo "[install_dropbear] Restart layanan..."
pkill -x dropbear 2>/dev/null || true
sleep 1
systemctl restart dropbear

echo "[install_dropbear] Verifikasi versi dari banner..."
BANNER=$(timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/143; head -1 <&3' 2>/dev/null || true)
echo "[install_dropbear] Banner: $BANNER"
case "$BANNER" in
    *dropbear_${VERSION}*) echo "[install_dropbear] OK: Dropbear ${VERSION} aktif." ;;
    *) echo "[install_dropbear] PERINGATAN: banner bukan ${VERSION}, periksa layanan!"; exit 1 ;;
esac

echo "[install_dropbear] Verifikasi handshake dengan cipher lama..."
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o PreferredAuthentications=none -c aes128-cbc,3des-cbc -m hmac-sha1-96 -p 143 root@127.0.0.1 true 2>&1 | grep -qE "no matching cipher|refused|failed"; then
    echo "[install_dropbear] PERINGATAN: cipher lama masih tidak tersedia!"
else
    echo "[install_dropbear] OK: handshake cipher lama diterima."
fi

echo "[install_dropbear] Status layanan:"
systemctl status dropbear --no-pager | head -8
echo "[install_dropbear] Selesai."
