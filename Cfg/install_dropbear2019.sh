#!/bin/bash
set -Eeuo pipefail

trap 'echo "[ERROR] Instalasi gagal pada baris ${LINENO}. Periksa pesan di atas." >&2' ERR

echo "=== INSTALL DROPBEAR 2019.78 ==="

# STOP DROPBEAR LAMA (TIDAK MENGHAPUS OPENSSH)
systemctl stop dropbear 2>/dev/null || true
systemctl disable dropbear 2>/dev/null || true
apt-get purge -y dropbear 2>/dev/null || true
apt-get remove -y dropbear 2>/dev/null || true

# DEPENDENCY
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential zlib1g-dev wget ca-certificates

# DOWNLOAD SOURCE
mkdir -p /usr/local/src
cd /usr/local/src
rm -rf dropbear-2019.78 dropbear-2019.78.tar.bz2
wget -O dropbear-2019.78.tar.bz2 https://matt.ucc.asn.au/dropbear/releases/dropbear-2019.78.tar.bz2
tar -xjf dropbear-2019.78.tar.bz2
cd /usr/local/src/dropbear-2019.78

# BUILD
./configure --prefix=/usr/local
make -j"$(nproc)"

# Pastikan hasil build server tersedia sebelum instalasi
if [ ! -s ./dropbear ]; then
    echo "[ERROR] Hasil kompilasi ./dropbear tidak ditemukan." >&2
    exit 1
fi

# INSTALL BINARY SECARA EKSPLISIT KE PATH SERVICE
install -d -m 0755 /usr/local/sbin /usr/local/bin
cp -f ./dropbear /usr/local/sbin/dropbear
chmod 0755 /usr/local/sbin/dropbear

# Install utilitas Dropbear
if [ -s ./dropbearkey ]; then
    cp -f ./dropbearkey /usr/local/bin/dropbearkey
    chmod 0755 /usr/local/bin/dropbearkey
fi

# Validasi binary; jangan lanjut jika target tidak ada/tidak executable
if [ ! -x /usr/local/sbin/dropbear ]; then
    echo "[ERROR] Binary gagal dipasang ke /usr/local/sbin/dropbear." >&2
    ls -lah /usr/local/src/dropbear-2019.78/dropbear /usr/local/sbin/ >&2 || true
    exit 1
fi
if [ ! -x /usr/local/bin/dropbearkey ]; then
    echo "[ERROR] dropbearkey tidak tersedia di /usr/local/bin/dropbearkey." >&2
    exit 1
fi

# SYMLINK KOMPATIBILITAS UNTUK SCRIPT LAMA
ln -sfn /usr/local/sbin/dropbear /usr/sbin/dropbear

# HOST KEY: PERTAHANKAN KEY YANG SUDAH ADA
install -d -m 0700 /etc/dropbear
if [ ! -s /etc/dropbear/dropbear_rsa_host_key ]; then
    /usr/local/bin/dropbearkey -t rsa -s 3072 -f /etc/dropbear/dropbear_rsa_host_key
fi
if [ ! -s /etc/dropbear/dropbear_ecdsa_host_key ]; then
    /usr/local/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
fi
chmod 0600 /etc/dropbear/dropbear_rsa_host_key /etc/dropbear/dropbear_ecdsa_host_key

# BANNER
if [ ! -f /etc/banner.txt ]; then
    install -m 0644 /dev/null /etc/banner.txt
fi

# SERVICE: TENTUKAN HOST KEY RSA + ECDSA SECARA EKSPLISIT
cat > /etc/systemd/system/dropbear.service <<'EOL'
[Unit]
Description=Dropbear SSH Server (2019)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/dropbear -F -E -p 109 -p 143 -W 65536 -I 60 -b /etc/banner.txt -r /etc/dropbear/dropbear_rsa_host_key -r /etc/dropbear/dropbear_ecdsa_host_key
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOL

# VALIDASI TERAKHIR SEBELUM SYSTEMD START
/usr/local/sbin/dropbear -V

# ENABLE + START
systemctl daemon-reload
systemctl reset-failed dropbear 2>/dev/null || true
systemctl enable dropbear
systemctl restart dropbear

sleep 2
echo ""
echo "=== STATUS ==="
systemctl status dropbear --no-pager -l || true

if ! systemctl is-active --quiet dropbear; then
    echo "[ERROR] Dropbear belum aktif. Log terakhir:" >&2
    journalctl -u dropbear -n 40 --no-pager >&2
    exit 1
fi

echo ""
echo "=== LISTEN PORT ==="
ss -lntp | grep -E ':(109|143)\\b' || true

echo ""
echo "=== BINARY ==="
ls -lh /usr/local/sbin/dropbear /usr/local/bin/dropbearkey

echo ""
echo "=== DONE: DROPBEAR ACTIVE ==="
