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
./configure
make -j"$(nproc)"

# INSTALL DROPBEAR BINARY
mkdir -p /usr/local/sbin
install -m 0755 ./dropbear /usr/local/sbin/dropbear

# SYMLINK
ln -sfn /usr/local/sbin/dropbear /usr/sbin/dropbear

# INSTALL DROPBEARKEY
if [ -x ./dropbearkey ]; then
    install -m 0755 ./dropbearkey /usr/local/bin/dropbearkey
fi

# HOSTKEY
mkdir -p /etc/dropbear

if [ ! -s /etc/dropbear/dropbear_rsa_host_key ]; then
    /usr/local/bin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key
fi

if [ ! -s /etc/dropbear/dropbear_ecdsa_host_key ]; then
    /usr/local/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key
fi

chmod 600 /etc/dropbear/dropbear_*_host_key
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

# ENABLE AND START
systemctl daemon-reload
systemctl enable dropbear
systemctl reset-failed dropbear 2>/dev/null || true
systemctl restart dropbear

# CHECK
sleep 2

if systemctl is-active --quiet dropbear; then
    echo "DROPBEAR BERHASIL DIINSTALL DAN RUNNING"
else
    echo "DROPBEAR GAGAL RUNNING"
    journalctl -u dropbear -n 30 --no-pager
    exit 1
fi

echo ""
echo "===== DROPBEAR STATUS ====="
systemctl status dropbear --no-pager -l

echo ""
echo "===== DROPBEAR PORT ====="
ss -tulpn | grep dropbear || true

echo ""
echo "===== DROPBEAR VERSION ====="
/usr/local/sbin/dropbear -V
