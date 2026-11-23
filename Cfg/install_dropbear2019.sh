#!/bin/bash
set -Eeuo pipefail

trap 'echo "[ERROR] Instalasi gagal pada baris ${LINENO}. Periksa pesan di atas." >&2' ERR

 echo "=== INSTALL DROPBEAR 2019.78 ==="

# STOP DAN HAPUS DROPBEAR LAMA (OpenSSH TIDAK DIHAPUS)
systemctl stop dropbear 2>/dev/null || true
systemctl disable dropbear 2>/dev/null || true
apt purge -y dropbear || true
apt remove -y dropbear 2>/dev/null || true
rm -f /usr/sbin/dropbear

# DEPENDENCY
apt update -y
apt install -y build-essential zlib1g-dev wget

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
make install

# PASTIKAN BINARY SERVER TERPASANG DI LOKASI SERVICE
mkdir -p /usr/local/sbin /usr/local/bin
install -m 0755 ./dropbear /usr/local/sbin/dropbear

# PASTIKAN DROPBEARKEY TERSEDIA
if [ -x ./dropbearkey ]; then
    install -m 0755 ./dropbearkey /usr/local/bin/dropbearkey
fi
if [ ! -x /usr/local/bin/dropbearkey ]; then
    echo "[ERROR] Binary dropbearkey tidak ditemukan setelah proses build." >&2
    exit 1
fi

# SYMLINK UNTUK KOMPATIBILITAS SCRIPT LAMA
ln -sfn /usr/local/sbin/dropbear /usr/sbin/dropbear

# HOSTKEY: PERTAHANKAN KEY LAMA AGAR FINGERPRINT SERVER TIDAK BERUBAH
mkdir -p /etc/dropbear
if [ ! -s /etc/dropbear/dropbear_rsa_host_key ]; then
    /usr/local/bin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
fi
if [ ! -s /etc/dropbear/dropbear_ecdsa_host_key ]; then
    /usr/local/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
fi
chmod 600 /etc/dropbear/dropbear_*_host_key

# BANNER: BUAT FILE KOSONG HANYA JIKA BELUM ADA
if [ ! -f /etc/banner.txt ]; then
    touch /etc/banner.txt
fi

# SERVICE
cat > /etc/systemd/system/dropbear.service <<'EOL'
[Unit]
Description=Dropbear SSH Server (2019)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/dropbear -EF -p 109 -p 143 -W 65536 -I 60 -b /etc/banner.txt
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOL

# ENABLE DAN START SERVICE
systemctl daemon-reload
systemctl reset-failed dropbear 2>/dev/null || true
systemctl enable dropbear
systemctl restart dropbear

# CHECK
sleep 2
echo ""
echo "=== STATUS ==="
systemctl status dropbear --no-pager -l

if ! systemctl is-active --quiet dropbear; then
    echo "[ERROR] Dropbear belum aktif. Log terakhir:" >&2
    journalctl -u dropbear -n 40 --no-pager >&2
    exit 1
fi

echo ""
echo "=== PORT ==="
ss -tulpn | grep -E 'dropbear|:109|:143' || true

echo ""
echo "=== VERSION ==="
/usr/local/sbin/dropbear -V

echo ""
echo "=== DONE: DROPBEAR ACTIVE ==="
