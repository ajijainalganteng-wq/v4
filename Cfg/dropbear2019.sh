
#!/bin/bash
# install_dropbear2019.sh
# Dropbear 2019.78 - Source Build + Custom Systemd Service

set -Eeuo pipefail

VERSION="2019.78"
URL="https://github.com/mkj/dropbear/archive/refs/tags/DROPBEAR_${VERSION}.tar.gz"

echo "[Dropbear] Menghentikan service lama..."
systemctl stop dropbear 2>/dev/null || true

echo "[Dropbear] Menginstal dependensi..."
apt-get update -y || true
apt-get install -y build-essential zlib1g-dev libtomcrypt-dev \
    libtommath-dev wget ca-certificates autoconf openssh-client

apt-get install -y libcrypt-dev 2>/dev/null || \
apt-get install -y libxcrypt-dev 2>/dev/null || true

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"

echo "[Dropbear] Download source ${VERSION}..."

DL_OK=0
for i in 1 2 3; do
    if wget --timeout=30 --tries=2 -q "$URL" -O dropbear.tar.gz &&
       tar tzf dropbear.tar.gz >/dev/null 2>&1; then
        DL_OK=1
        break
    fi
    sleep 5
done

[ "$DL_OK" = 1 ] || {
    echo "[ERROR] Gagal mengunduh source Dropbear."
    exit 1
}

tar xzf dropbear.tar.gz
cd "dropbear-DROPBEAR_${VERSION}"

# Generate configure files jika belum tersedia
if [ ! -f configure ]; then
    autoconf
fi

if [ ! -f config.h.in ]; then
    autoheader
fi

echo "[Dropbear] Mengaktifkan algoritma legacy..."

sed -i 's/^#define DROPBEAR_ENABLE_CBC_MODE 0/#define DROPBEAR_ENABLE_CBC_MODE 1/' default_options.h
sed -i 's/^#define DROPBEAR_3DES 0/#define DROPBEAR_3DES 1/' default_options.h
sed -i 's/^#define DROPBEAR_SHA1_96_HMAC 0/#define DROPBEAR_SHA1_96_HMAC 1/' default_options.h
sed -i 's/^#define DROPBEAR_DH_GROUP1_CLIENTONLY 1/#define DROPBEAR_DH_GROUP1_CLIENTONLY 0/' default_options.h

echo "[Dropbear] Build source..."

if ! ./configure --prefix=/usr --sysconfdir=/etc --disable-pam >/dev/null 2>&1 ||
   ! make -j"$(nproc)" PROGRAMS="dropbear dropbearkey dropbearconvert" >/dev/null 2>&1; then

    echo "[Dropbear] Mencoba bundled libtom..."

    make distclean >/dev/null 2>&1 || true

    ./configure --prefix=/usr --sysconfdir=/etc \
        --disable-pam --enable-bundled-libtom

    make -j"$(nproc)" PROGRAMS="dropbear dropbearkey dropbearconvert"
fi

echo "[Dropbear] Memasang binary..."

install -D -m 0755 dropbear /usr/sbin/dropbear
install -D -m 0755 dropbearkey /usr/sbin/dropbearkey
install -D -m 0755 dropbearconvert /usr/sbin/dropbearconvert

# Pastikan binary tersedia
test -x /usr/sbin/dropbear
test -x /usr/sbin/dropbearkey

echo "[Dropbear] Membuat host key..."

mkdir -p /etc/dropbear

[ -s /etc/dropbear/dropbear_rsa_host_key ] ||
    /usr/sbin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key

[ -s /etc/dropbear/dropbear_ecdsa_host_key ] ||
    /usr/sbin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key

[ -s /etc/dropbear/dropbear_dss_host_key ] ||
    /usr/sbin/dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key

chmod 600 /etc/dropbear/dropbear_*_host_key

# Jangan menimpa banner yang sudah dibuat pengguna
touch /etc/banner.txt

echo "[Dropbear] Menyinkronkan konfigurasi..."

cat > /etc/default/dropbear <<'EOF'
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109 -W 65536 -I 60 -b /etc/banner.txt"
DROPBEAR_BANNER="/etc/banner.txt"
DROPBEAR_RECEIVE_WINDOW=65536
EOF

chmod 644 /etc/default/dropbear

echo "[Dropbear] Membuat systemd service..."

cat > /etc/systemd/system/dropbear.service <<'EOF'
[Unit]
Description=Dropbear SSH Server 2019.78
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/dropbear -F -E -p 109 -p 143 -W 65536 -I 60 -b /etc/banner.txt -r /etc/dropbear/dropbear_rsa_host_key -r /etc/dropbear/dropbear_ecdsa_host_key -r /etc/dropbear/dropbear_dss_host_key
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "[Dropbear] Mencegah apt menimpa paket..."

apt-mark hold dropbear dropbear-bin >/dev/null 2>&1 || true

echo "[Dropbear] Mengaktifkan service..."

systemctl daemon-reload
systemctl reset-failed dropbear 2>/dev/null || true
systemctl enable dropbear
systemctl restart dropbear

sleep 2

echo "[Dropbear] Memeriksa service..."

if ! systemctl is-active --quiet dropbear; then
    echo "[ERROR] Dropbear gagal berjalan!"
    journalctl -u dropbear -n 40 --no-pager
    exit 1
fi

echo "[Dropbear] Memeriksa banner..."

BANNER=$(timeout 5 bash -c \
    'exec 3<>/dev/tcp/127.0.0.1/143; head -n 1 <&3' \
    2>/dev/null || true)

echo "Banner: $BANNER"

case "$BANNER" in
    *dropbear_2019.78*)
        echo "[OK] Dropbear 2019.78 aktif."
        ;;
    *)
        echo "[ERROR] Banner versi tidak sesuai!"
        journalctl -u dropbear -n 30 --no-pager
        exit 1
        ;;
esac

echo ""
echo "===== DROPBEAR VERSION ====="
/usr/sbin/dropbear -V

echo ""
echo "===== DROPBEAR SERVICE ====="
systemctl status dropbear --no-pager -l

echo ""
echo "===== DROPBEAR PORT ====="
ss -tulpn | grep dropbear || true

echo ""
echo "[SUCCESS] Instalasi Dropbear 2019.78 selesai."
