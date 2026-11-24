#!/bin/bash
set -Eeuo pipefail

trap 'echo "[ERROR] Instalasi gagal pada baris ${LINENO}. Periksa pesan di atas." >&2' ERR

echo "=== INSTALL DROPBEAR 2019.78 ==="

# ROOT CHECK
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Jalankan script sebagai root!"
    exit 1
fi

# STOP DROPBEAR LAMA (TIDAK MENGHAPUS OPENSSH)
systemctl stop dropbear 2>/dev/null || true
systemctl disable dropbear 2>/dev/null || true

apt-get purge -y dropbear 2>/dev/null || true
apt-get remove -y dropbear 2>/dev/null || true

# DEPENDENCY
apt-get update -y

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    zlib1g-dev \
    wget \
    ca-certificates \
    file

# DOWNLOAD SOURCE
mkdir -p /usr/local/src
cd /usr/local/src

rm -rf dropbear-2019.78 dropbear-2019.78.tar.bz2

wget -O dropbear-2019.78.tar.bz2 \
    https://matt.ucc.asn.au/dropbear/releases/dropbear-2019.78.tar.bz2

tar -xjf dropbear-2019.78.tar.bz2

cd /usr/local/src/dropbear-2019.78

# BUILD
echo "=== BUILD DROPBEAR ==="

./configure
make -j"$(nproc)"

# VERIFY BUILD
if [ ! -f ./dropbear ]; then
    echo "[ERROR] Binary hasil kompilasi tidak ditemukan!"
    exit 1
fi

# INSTALL DROPBEAR BINARY
mkdir -p /usr/local/sbin

if [ ! -s ./dropbear ]; then
    echo "[ERROR] Binary hasil build tidak ditemukan!"
    exit 1
fi

install -m 0755 ./dropbear /usr/local/sbin/dropbear

# VERIFY INSTALLATION
if [ ! -x /usr/local/sbin/dropbear ]; then
    echo "[ERROR] Instalasi binary gagal!"
    exit 1
fi

# SYMLINK
ln -sfn /usr/local/sbin/dropbear /usr/sbin/dropbear

echo "[OK] Binary Dropbear berhasil dipasang"
# VERIFY INSTALLED BINARY
if [ ! -f /usr/local/sbin/dropbear ] || [ ! -x /usr/local/sbin/dropbear ]; then
    echo "[ERROR] Binary Dropbear tidak valid!"
    exit 1
fi

if ! /usr/local/sbin/dropbear -V; then
    echo "[ERROR] Binary Dropbear tidak dapat dieksekusi!"
    exit 1
fi

echo "[OK] Binary Dropbear berhasil dipasang"

# INSTALL DROPBEARKEY
if [ -x ./dropbearkey ]; then
    install -D -m 0755 ./dropbearkey /usr/local/bin/dropbearkey
fi

if [ ! -x /usr/local/bin/dropbearkey ]; then
    echo "[ERROR] Dropbearkey tidak ditemukan!"
    exit 1
fi

# HOSTKEY
mkdir -p /etc/dropbear

if [ ! -s /etc/dropbear/dropbear_rsa_host_key ]; then
    /usr/local/bin/dropbearkey \
        -t rsa \
        -f /etc/dropbear/dropbear_rsa_host_key
fi

if [ ! -s /etc/dropbear/dropbear_ecdsa_host_key ]; then
    /usr/local/bin/dropbearkey \
        -t ecdsa \
        -f /etc/dropbear/dropbear_ecdsa_host_key
fi

chmod 600 /etc/dropbear/dropbear_*_host_key

# BANNER
touch /etc/banner.txt

# SERVICE
cat > /etc/systemd/system/dropbear.service <<'EOL'
[Unit]
Description=Dropbear SSH Server (2019)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/dropbear -F -E -p 109 -p 143 -W 65536 -I 60 -b /etc/banner.txt
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOL

# VERIFY SERVICE EXECUTABLE
if [ ! -x /usr/local/sbin/dropbear ]; then
    echo "[ERROR] ExecStart binary tidak tersedia!"
    exit 1
fi

# ENABLE AND START
echo "=== START DROPBEAR SERVICE ==="

systemctl daemon-reload
systemctl enable dropbear

systemctl reset-failed dropbear 2>/dev/null || true
systemctl restart dropbear

# CHECK
sleep 2

if systemctl is-active --quiet dropbear; then
    echo ""
    echo "=================================="
    echo " DROPBEAR BERHASIL RUNNING"
    echo "=================================="
else
    echo ""
    echo "[ERROR] DROPBEAR GAGAL RUNNING"
    journalctl -u dropbear -n 40 --no-pager
    exit 1
fi

# STATUS
echo ""
echo "===== DROPBEAR STATUS ====="
systemctl status dropbear --no-pager -l

echo ""
echo "===== DROPBEAR PORT ====="
ss -tulpn | grep dropbear || true

echo ""
echo "===== DROPBEAR VERSION ====="
/usr/local/sbin/dropbear -V

echo ""
echo "=== INSTALLATION COMPLETE ==="
