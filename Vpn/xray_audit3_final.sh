#!/bin/bash
Green="\e[92;1m"
RED="\033[1;31m"
YELLOW="\033[33m"
BLUE="\033[36m"
FONT="\033[0m"
GREENBG="\033[42;37m"
REDBG="\033[41;37m"
OK="${Green}--->${FONT}"
ERROR="${RED}[ERROR]${FONT}"
GRAY="\e[1;30m"
NC='\e[0m'
red='\e[1;31m'
green='\e[0;32m'
TIME=$(date '+%d %b %Y')
TIMES="10"
CHATID="1962241851"
KEY="8238209608:AAGflWVin-HM9sSar6Fyif6E7SMJF0FgShY"
URL="https://api.telegram.org/bot$KEY/sendMessage"
function print_ok() {
echo -e "${OK} ${BLUE} $1 ${FONT}"
}
function print_install() {
echo -e "${green} =============================== ${FONT}"
echo -e "${YELLOW} # $1 ${FONT}"
echo -e "${green} =============================== ${FONT}"
sleep 1
}
function print_error() {
echo -e "${ERROR} ${REDBG} $1 ${FONT}"
}
function print_success() {
if [[ 0 -eq $? ]]; then
echo -e "${green} =============================== ${FONT}"
echo -e "${Green} # $1 berhasil dipasang"
echo -e "${green} =============================== ${FONT}"
sleep 2
fi
}      
clear
    function check_os_version() {
    # Version-independent check: this installer relies on APT/systemd and is
    # therefore intended for Debian-family VPS distributions. No release
    # numbers are hard-coded, so new Debian/Ubuntu releases are accepted.
    if [ ! -r /etc/os-release ]; then
        print_error "/etc/os-release tidak ditemukan."
        exit 1
    fi

    . /etc/os-release
    local distro="${ID:-unknown}"
    local like="${ID_LIKE:-}"

    case " ${distro} ${like} " in
        *" debian "*|*" ubuntu "*)
            print_ok "OS Supported: ${PRETTY_NAME:-$distro}"
            ;;
        *)
            print_error "OS ${PRETTY_NAME:-$distro} belum kompatibel dengan dependency installer ini."
            print_error "Kode menu VPN/download tetap dipertahankan; bagian OS-specific membutuhkan paket/service manager Debian-family."
            exit 1
            ;;
    esac
}

case "$(uname -m)" in
    x86_64|aarch64|armv7l|armv6l)
        print_ok "Architecture Supported: $(uname -m)"
        ;;
    *)
        print_error "Architecture Not Supported: $(uname -m)"
        exit 1
        ;;
esac

# Cek OS (tanpa hard-coded release version)
check_os_version

# AUDIT 3 FINAL PREFLIGHT
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { print_error "Command wajib tidak tersedia: $1"; exit 1; }
}
for _cmd in bash awk sed grep curl wget ip systemctl date mkdir chmod; do require_cmd "$_cmd"; done
if [ ! -d /run/systemd/system ]; then
    print_error "systemd tidak aktif. Installer ini membutuhkan systemd."
    exit 1
fi
if [ ! -w /etc ] || [ ! -w /usr/local ]; then
    print_error "Filesystem sistem tidak writable/read-only."
    exit 1
fi

if [ "${EUID}" -ne 0 ]; then
   print_error "You need to run this script as root"
   exit 1
fi
if [ "$(systemd-detect-virt)" == "openvz" ]; then
   print_error "OpenVZ is not supported"
   exit 1
fi
# ------------------------------------------------------------
# Base dependencies
# Keep this list small and compatible with current Debian/Ubuntu.
# Do not run full upgrade/dist-upgrade during installer execution:
# it is slow and can introduce unrelated package/service changes.
# ------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends \
    bash curl wget ca-certificates \
    coreutils sed grep gawk awk findutils \
    iproute2 iputils-ping \
    jq openssl tar gzip bzip2 xz-utils zip unzip \
    git cron at \
    python3 python3-pip \
    socat netcat-openbsd \
    lsof procps htop \
    rsyslog bc \
    gnupg dnsutils \
    gcc g++ make cmake pkg-config \
    libnss3 libnspr4 libsqlite3-0 \
    openssh-client sudo \
    screen figlet

# Optional UI/tools: never make the core installer fail because these are
# unavailable on a newer repository snapshot.
apt-get install -y --no-install-recommends ruby ruby-rubygems 2>/dev/null || true
apt-get install -y --no-install-recommends lolcat 2>/dev/null || true
apt-get install -y --no-install-recommends dos2unix 2>/dev/null || true
apt-get install -y --no-install-recommends telnet 2>/dev/null || true
apt-get install -y --no-install-recommends wondershaper 2>/dev/null || true
apt-get install -y --no-install-recommends speedtest-cli 2>/dev/null || true
apt-get install -y --no-install-recommends vnstat 2>/dev/null || true
apt-get install -y --no-install-recommends iptables iptables-persistent netfilter-persistent 2>/dev/null || true
apt-get install -y --no-install-recommends openvpn easy-rsa 2>/dev/null || true
apt-get install -y --no-install-recommends fail2ban 2>/dev/null || true

# Some older scripts call `python`; current Debian/Ubuntu normally provide
# python3 only. Create a compatibility symlink only when `python` is absent.
if ! command -v python >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    ln -sf "$(command -v python3)" /usr/local/bin/python
fi

# lolcat is cosmetic. Prefer the distro package; RubyGems is only a fallback.
if ! command -v lolcat >/dev/null 2>&1 && command -v gem >/dev/null 2>&1; then
    gem install lolcat --no-document 2>/dev/null || true
fi

# Current VPS images may not ship a separate chrony service. Time sync is
# best-effort and must never abort the VPN installation.
if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone Asia/Jakarta 2>/dev/null || true
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now chrony 2>/dev/null || \
    systemctl enable --now chronyd 2>/dev/null || true
fi

# `ntpdate` is obsolete on many current releases; do not require it.
if command -v chronyc >/dev/null 2>&1; then
    chronyc -a makestep >/dev/null 2>&1 || true
fi

if [[ -z "${IP:-}" ]]; then
echo -e "${EROR} IP Address ( ${RED}Not Detected${NC} )"
else
echo -e "${OK} IP Address ( ${green}${IP:-Not Detected}${NC} )"
fi
echo ""
echo "Process ${GRAY}[ ${NC}${green}Install${NC} ${GRAY}]${NC} For Starting Installation "
echo ""
clear
if [ "${EUID}" -ne 0 ]; then
echo "You need to run this script as root"
exit 1
fi
if [ "$(systemd-detect-virt)" == "openvz" ]; then
echo "OpenVZ is not supported"
exit 1
fi
echo -e "\e[32mloading...\e[0m"
clear
REPO="https://raw.githubusercontent.com/arivpnstores/v4/main/"
start=$(date +%s)
secs_to_human() {
echo "Installation time : $((${1} / 3600)) hours $(((${1} / 60) % 60)) minute's $((${1} % 60)) seconds"
}
function is_root() {
if [[ 0 == "$UID" ]]; then
print_ok "Root user Start installation process"
else
print_error "The current user is not the root user, please switch to the root user and run the script again"
fi
}
clear
print_install "Membuat direktori xray"
mkdir -p /etc/xray
curl -s ifconfig.me > /etc/xray/ipvps
mkdir -p /var/log/xray
chown www-data.www-data /var/log/xray
chmod 755 /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log
mkdir -p /var/lib/kyt >/dev/null 2>&1
while IFS=":" read -r a b; do
case $a in
"MemTotal") ((mem_used+=${b/kB})); mem_total="${b/kB}" ;;
"Shmem") ((mem_used+=${b/kB}))  ;;
"MemFree" | "Buffers" | "Cached" | "SReclaimable")
mem_used="$((mem_used-=${b/kB}))"
;;
esac
done < /proc/meminfo
Ram_Usage="$((mem_used / 1024))"
Ram_Total="$((mem_total / 1024))"
export tanggal=`date -d "0 days" +"%d-%m-%Y - %X" `
export OS_Name=$( cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/PRETTY_NAME//g' | sed 's/=//g' | sed 's/"//g' )
export Kernel=$( uname -r )
export Arch=$( uname -m )
export IP=$( curl -s https://ipinfo.io/ip/ )
function first_setup(){
    timedatectl set-timezone Asia/Jakarta 2>/dev/null || true

    print_success "Directory Xray"

    # Do not pin HAProxy 1.8/2.0 or use the old buster repository/PPA.
    # Install the version supplied by the current OS repository.
    print_install "Installing HAProxy from current OS repository"
    apt-get update -y
    if ! apt-get install -y --no-install-recommends haproxy; then
        print_error "HAProxy gagal dipasang dari repository OS."
        exit 1
    fi
}
clear
function nginx_install() {
clear
print_install "Setup nginx"
if ! apt-get install -y --no-install-recommends nginx; then
    print_error "nginx gagal dipasang."
    return 1
fi
systemctl enable nginx >/dev/null 2>&1 || true
print_success "nginx"
}
clear
restart_system() {
domainNOTIF=$(cat /etc/xray/domain)
USRSC=$(cat /usr/bin/user)
EXPSC=$(cat /usr/bin/e)
TIMEZONE=$(printf '%(%H:%M:%S)T')
TEXT="
<code>────────────────────</code>
<b> 🟢 NOTIFICATIONS INSTALL 🟢</b>
<code>────────────────────</code>
<code>ID     : </code><code>$USRSC</code>
<code>Domain : </code><code>$domainNOTIF</code>
<code>Date   : </code><code>$TIME</code>
<code>Time   : </code><code>$TIMEZONE</code>
<code>Ip vps : </code><code>$ipsaya</code>
<code>Exp Sc : </code><code>$EXPSC</code>
<code>────────────────────</code>
<i>Automatic Notification from Github</i>
"'&reply_markup={"inline_keyboard":[[{"text":"ᴏʀᴅᴇʀ","url":"https://wa.me/AJIVPN"},{"text":"Contact","url":"https://wa.me/6287862591220"}]]}'
curl -s --max-time $TIMES -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
}
auto_system() {
    cron_file="/etc/cron.d/auto_update"
    pekerjaan_cron="15 1 * * * root /usr/bin/auto_update"

    # Periksa apakah pekerjaan cron sudah ada di file
    if ! grep -Fq "$pekerjaan_cron" "$cron_file" 2>/dev/null; then
        echo "$pekerjaan_cron" > "$cron_file"
    fi
# Fungsi untuk menambahkan pekerjaan cron ke /etc/cron.d/
    cron_file="/etc/cron.d/backup_otomatis"
    pekerjaan_cron="15 23 * * * root /usr/bin/backupfile"

    # Periksa apakah pekerjaan cron sudah ada di file
    if ! grep -Fq "$pekerjaan_cron" "$cron_file" 2>/dev/null; then
        echo "$pekerjaan_cron" > "$cron_file"
    fi
}

clear
function pasang_ssl() {
clear
while true; do
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -rp "Masukkan Domain VPS: " DOMAIN
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    DOMAIN="${DOMAIN,,}"
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN%%/*}"
    if [[ "$DOMAIN" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$ ]]; then break; fi
    echo "Domain tidak valid, silakan masukkan kembali."
done
echo "$DOMAIN" > /root/domain
mkdir -p /etc/xray
echo "$DOMAIN" > /etc/xray/domain
clear
print_install "Memasang SSL Pada Domain"
local backup_dir="/root/xray-ssl-backup-$(date +%s)"
mkdir -p "$backup_dir"
[ -s /etc/xray/xray.crt ] && cp -a /etc/xray/xray.crt "$backup_dir/xray.crt"
[ -s /etc/xray/xray.key ] && cp -a /etc/xray/xray.key "$backup_dir/xray.key"
local stop_pid
stop_pid=$(lsof -t -iTCP:80 -sTCP:LISTEN 2>/dev/null | head -n1 || true)
[ -n "$stop_pid" ] && kill "$stop_pid" 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true
mkdir -p /root/.acme.sh
if ! curl -fsSL --retry 3 --connect-timeout 10 https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh -o /root/.acme.sh/acme.sh; then
    print_error "Gagal mengunduh acme.sh"
    return 1
fi
chmod 700 /root/.acme.sh/acme.sh
if ! /root/.acme.sh/acme.sh --install --home /root/.acme.sh >/dev/null 2>&1; then
    print_error "Gagal menyiapkan acme.sh"
    return 1
fi
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
if ! /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256; then
    print_error "Penerbitan SSL gagal. Sertifikat lama tidak dihapus."
    return 1
fi
if ! /root/.acme.sh/acme.sh --install-cert -d "$DOMAIN" --fullchain-file /etc/xray/xray.crt --key-file /etc/xray/xray.key --ecc; then
    print_error "Instalasi file SSL gagal."
    return 1
fi
chown root:www-data /etc/xray/xray.key /etc/xray/xray.crt
chmod 640 /etc/xray/xray.key
chmod 644 /etc/xray/xray.crt
if [ ! -s /etc/xray/xray.crt ] || [ ! -s /etc/xray/xray.key ]; then
    print_error "SSL certificate/key tidak berhasil dibuat."
    return 1
fi
print_success "SSL Certificate"
}
function make_folder_xray() {
rm -rf /etc/vmess/.vmess.db
rm -rf /etc/vless/.vless.db
rm -rf /etc/trojan/.trojan.db
rm -rf /etc/shadowsocks/.shadowsocks.db
rm -rf /etc/ssh/.ssh.db
rm -rf /etc/bot/.bot.db
mkdir -p /etc/bot
mkdir -p /etc/xray
mkdir -p /etc/vmess
mkdir -p /etc/vless
mkdir -p /etc/trojan
mkdir -p /etc/shadowsocks
mkdir -p /etc/ssh
mkdir -p /usr/bin/xray/
mkdir -p /var/log/xray/
mkdir -p /var/www/html
mkdir -p /etc/kyt/limit/vmess/ip
mkdir -p /etc/kyt/limit/vless/ip
mkdir -p /etc/kyt/limit/trojan/ip
mkdir -p /etc/kyt/limit/ssh/ip
mkdir -p /etc/limit/vmess
mkdir -p /etc/limit/vless
mkdir -p /etc/limit/trojan
mkdir -p /etc/limit/ssh
chmod 755 /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log
touch /etc/vmess/.vmess.db
touch /etc/vless/.vless.db
touch /etc/trojan/.trojan.db
touch /etc/shadowsocks/.shadowsocks.db
touch /etc/ssh/.ssh.db
touch /etc/bot/.bot.db
echo "& plughin Account" >>/etc/vmess/.vmess.db
echo "& plughin Account" >>/etc/vless/.vless.db
echo "& plughin Account" >>/etc/trojan/.trojan.db
echo "& plughin Account" >>/etc/shadowsocks/.shadowsocks.db
echo "& plughin Account" >>/etc/ssh/.ssh.db
}
function install_xray() {
    clear
    print_install "Core Xray - detect versi & arsitektur otomatis"

    domainSock_dir="/run/xray"
    mkdir -p "$domainSock_dir"
    chown www-data:www-data "$domainSock_dir" 2>/dev/null || true

    # Do not pin an obsolete Xray version. The official installer selects the
    # current stable release and the correct architecture.
    if ! bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ install -u www-data; then
        print_error "Instalasi Xray gagal."
        exit 1
    fi

    # Keep the original remote configuration/download locations untouched.
    wget -O /etc/xray/config.json "${REPO}Cfg/config.json" >/dev/null 2>&1
    wget -O /etc/systemd/system/runn.service "${REPO}Fls/runn.service" >/dev/null 2>&1

    domain=$(cat /etc/xray/domain)
    IPVS=$(cat /etc/xray/ipvps)

    print_success "Core Xray"
    clear
    print_install "Memasang Konfigurasi Packet"

    mkdir -p /etc/haproxy /etc/nginx/conf.d
    wget -q -O /etc/haproxy/haproxy.cfg "${REPO}Cfg/haproxy.cfg" || { print_error "Gagal download haproxy.cfg"; exit 1; }
    wget -q -O /etc/nginx/conf.d/xray.conf "${REPO}Cfg/xray.conf" || { print_error "Gagal download xray.conf"; exit 1; }

    sed -i "s/xxx/${domain}/g" /etc/haproxy/haproxy.cfg 2>/dev/null || true
    sed -i "s/xxx/${domain}/g" /etc/nginx/conf.d/xray.conf 2>/dev/null || true
    curl -fsSL "${REPO}Cfg/nginx.conf" -o /etc/nginx/nginx.conf

    if [ -s /etc/xray/xray.crt ] && [ -s /etc/xray/xray.key ]; then
        cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/haproxy/hap.pem
        chmod 600 /etc/haproxy/hap.pem
    else
        print_error "Sertifikat Xray tidak ditemukan; konfigurasi HAProxy SSL dilewati."
    fi

    chmod +x /etc/systemd/system/runn.service 2>/dev/null || true

    # Generate a valid modern systemd unit. The original unit was invalid
    # because [Unit] was missing and `filesNPROC` was not a systemd directive.
    cat >/etc/systemd/system/xray.service <<'EOF'
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
Wants=network-online.target
After=network-online.target nss-lookup.target

[Service]
Type=simple
User=www-data
Group=www-data
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=2
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now xray 2>/dev/null || true

    print_success "Konfigurasi Packet"
}

function ssh(){
clear
print_install "Memasang Password SSH"
wget -O /etc/pam.d/common-password "${REPO}Fls/password"
chmod +x /etc/pam.d/common-password
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure keyboard-configuration
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/altgr select The default for the keyboard layout"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/compose select No compose key"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/ctrl_alt_bksp boolean false"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/layoutcode string de"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/layout select English"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/modelcode string pc105"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/model select Generic 105-key (Intl) PC"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/optionscode string "
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/store_defaults_in_debconf_db boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/switch select No temporary switch"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/toggle select No toggling"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_config_layout boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_config_options boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_layout boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_options boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/variantcode string "
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/variant select English"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/xkb-keymap select "
cd
cat > /etc/systemd/system/rc-local.service <<-END
[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local
[Service]
Type=oneshot
ExecStart=/etc/rc.local start
RemainAfterExit=yes
TimeoutStartSec=0
[Install]
WantedBy=multi-user.target
END
cat > /etc/rc.local <<-END
exit 0
END
chmod +x /etc/rc.local
systemctl enable rc-local
systemctl start rc-local.service
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local
ln -fs /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
sed -i 's/AcceptEnv/#AcceptEnv/g' /etc/ssh/sshd_config
print_success "Password SSH"
}
function udp_mini(){
clear
print_install "Memasang Service limit Quota"
wget -q -O /tmp/limit.sh https://raw.githubusercontent.com/arivpnstores/v4/main/Fls/limit.sh && chmod +x /tmp/limit.sh && bash /tmp/limit.sh
cd
wget -q -O /usr/bin/limit-ip "${REPO}Fls/limit-ip"
chmod 755 /usr/bin/limit-ip
cd /usr/bin
sed -i 's/\r//' limit-ip
cd
clear
cat >/etc/systemd/system/vmip.service << EOF
[Unit]
Description=My
After=network.target
[Service]
WorkingDirectory=/root
ExecStart=/usr/bin/limit-ip vmip
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl restart vmip
systemctl enable vmip
cat >/etc/systemd/system/vlip.service << EOF
[Unit]
Description=My
After=network.target
[Service]
WorkingDirectory=/root
ExecStart=/usr/bin/limit-ip vlip
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl restart vlip
systemctl enable vlip
cat >/etc/systemd/system/trip.service << EOF
[Unit]
Description=My
After=network.target
[Service]
WorkingDirectory=/root
ExecStart=/usr/bin/limit-ip trip
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl restart trip
systemctl enable trip
mkdir -p /usr/local/kyt/
wget -q -O /usr/local/kyt/udp-mini "${REPO}Fls/udp-mini"
chmod +x /usr/local/kyt/udp-mini
wget -q -O /etc/systemd/system/udp-mini-1.service "${REPO}Fls/udp-mini-1.service"
wget -q -O /etc/systemd/system/udp-mini-2.service "${REPO}Fls/udp-mini-2.service"
wget -q -O /etc/systemd/system/udp-mini-3.service "${REPO}Fls/udp-mini-3.service"
systemctl disable udp-mini-1
systemctl stop udp-mini-1
systemctl enable udp-mini-1
systemctl start udp-mini-1
systemctl disable udp-mini-2
systemctl stop udp-mini-2
systemctl enable udp-mini-2
systemctl start udp-mini-2
systemctl disable udp-mini-3
systemctl stop udp-mini-3
systemctl enable udp-mini-3
systemctl start udp-mini-3
print_success "files Quota Service"
}
function ssh_slow(){
clear
print_install "Memasang modul SlowDNS Server"
wget -q -O /tmp/nameserver "${REPO}Fls/nameserver" >/dev/null 2>&1
chmod +x /tmp/nameserver
bash /tmp/nameserver | tee /root/install.log
clear
print_success "SlowDNS"
}
clear
function ins_SSHD(){
clear
print_install "Memasang SSHD"
local backup="/etc/ssh/sshd_config.audit3.bak"
[ -f /etc/ssh/sshd_config ] && cp -a /etc/ssh/sshd_config "$backup"
if ! wget -q -O /etc/ssh/sshd_config "${REPO}Fls/sshd"; then
    print_error "Gagal download sshd_config"
    [ -f "$backup" ] && cp -a "$backup" /etc/ssh/sshd_config
    return 1
fi
chmod 600 /etc/ssh/sshd_config
if ! sshd -t; then
    print_error "sshd_config tidak valid; konfigurasi lama dipulihkan."
    [ -f "$backup" ] && cp -a "$backup" /etc/ssh/sshd_config
    return 1
fi
if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; then
    print_success "SSHD"
else
    print_error "SSH gagal restart."
    return 1
fi
}
clear
function ins_dropbear(){
clear
print_install "Menginstall Dropbear"
if ! apt-get install -y --no-install-recommends dropbear >/dev/null 2>&1; then
    print_error "Dropbear gagal dipasang"
    return 1
fi
if ! wget -q -O /etc/default/dropbear "${REPO}Cfg/dropbear.conf"; then
    print_error "Gagal download konfigurasi Dropbear"
    return 1
fi
chmod 600 /etc/default/dropbear
systemctl restart dropbear 2>/dev/null || true
systemctl is-active --quiet dropbear || { print_error "Dropbear tidak aktif"; return 1; }
print_success "Dropbear"
}
clear
function ins_vnstat(){
    clear
    print_install "Menginstall Vnstat"

    apt-get install -y --no-install-recommends vnstat libsqlite3-0 2>/dev/null || {
        print_error "vnstat gagal dipasang."
        return 1
    }

    local net_interface
    net_interface=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1)

    if [ -n "$net_interface" ]; then
        vnstat -u -i "$net_interface" --force 2>/dev/null || true
    else
        print_error "Interface default tidak ditemukan; vnstat akan tetap terpasang."
    fi

    systemctl enable --now vnstat 2>/dev/null || true
    print_success "Vnstat"
}

function ins_openvpn(){
clear
print_install "Menginstall OpenVPN"
if ! wget -q -O /root/openvpn-installer "${REPO}Fls/openvpn"; then
    print_error "Gagal download installer OpenVPN"
    return 1
fi
chmod +x /root/openvpn-installer
if ! bash /root/openvpn-installer; then
    print_error "Installer OpenVPN gagal"
    return 1
fi
systemctl restart openvpn 2>/dev/null || systemctl restart openvpn-server@server 2>/dev/null || true
print_success "OpenVPN"
}
function ins_backup() {
    clear
    print_install "Memasang Backup Server"
    apt install rclone -y
    printf "q\n" | rclone config
    wget -O /root/.config/rclone/rclone.conf "${REPO}Cfg/rclone.conf"

    cd /bin
    git clone https://github.com/arivpnstores/wondershaper.git
    cd wondershaper
    sudo make install
    cd
    rm -rf wondershaper

    echo > /home/files

    apt install msmtp-mta ca-certificates bsd-mailx -y

    cat <<EOF > /etc/msmtprc
defaults
tls on
tls_starttls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
account default
host smtp.gmail.com
port 587
auth on
user oceantestdigital@gmail.com
from oceantestdigital@gmail.com
password jokerman77
logfile ~/.msmtp.log
EOF

    chown -R www-data:www-data /etc/msmtprc

    wget -q -O /etc/ipserver "${REPO}Fls/ipserver" && bash /etc/ipserver
    print_success "Backup Server"
}
clear
function ins_swab(){
clear
print_install "Memasang Swap 2 GB"
# gotop is optional; skip it when the upstream release does not provide a
# package for this architecture.
GOTOP_ARCH=""
case "$(uname -m)" in
    x86_64) GOTOP_ARCH="amd64" ;;
    aarch64) GOTOP_ARCH="arm64" ;;
esac
if [ -n "$GOTOP_ARCH" ]; then
    gotop_latest="$(curl -fsSL https://api.github.com/repos/xxxserxxx/gotop/releases/latest 2>/dev/null | sed -n 's/.*"tag_name":[[:space:]]*"v\([^"]*\)".*/\1/p' | head -n1)"
    gotop_link="https://github.com/xxxserxxx/gotop/releases/download/v${gotop_latest}/gotop_v${gotop_latest}_linux_${GOTOP_ARCH}.deb"
    curl -fsSL "$gotop_link" -o /tmp/gotop.deb 2>/dev/null && dpkg -i /tmp/gotop.deb >/dev/null 2>&1 || true
fi
dd if=/dev/zero of=/swapfile bs=1M count=2048
mkswap /swapfile
chown root:root /swapfile
chmod 0600 /swapfile >/dev/null 2>&1
swapon /swapfile >/dev/null 2>&1
sed -i '$ i\/swapfile      swap swap   defaults    0 0' /etc/fstab
chronyd -q 'server 0.id.pool.ntp.org iburst'
chronyc sourcestats -v
chronyc tracking -v
wget ${REPO}Fls/bbr.sh &&  chmod +x bbr.sh && ./bbr.sh
print_success "Swap 2 GB"
}
function ins_Fail2ban() {
    clear
     print_install "Menginstall Fail2ban"
    
    if [ -d '/usr/local/ddos' ]; then
        echo; echo; echo "Please un-install the previous version first"
        exit 0
    else
        mkdir /usr/local/ddos
    fi

    clear
    echo "Banner /etc/banner.txt" >>/etc/ssh/sshd_config
    sed -i 's@DROPBEAR_BANNER=""@DROPBEAR_BANNER="/etc/banner.txt"@g' /etc/default/dropbear
    wget -O /etc/banner.txt "${REPO}banner.txt"
    
    # Install dan Konfigurasi Fail2ban
    echo "Menginstal Fail2ban..."

    # Instal Fail2ban
    apt-get update
    apt-get install -y fail2ban

    # Konfigurasi Fail2ban untuk memantau log tertentu
    cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = systemd

[http-get-dos]
enabled  = true
port     = http,https
filter   = http-get-dos
logpath  = /var/log/nginx/access.log
maxretry = 200
findtime = 200
bantime  = 600

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
action  = iptables-allports[name=recidive]
bantime  = 604800  ; 1 week
findtime = 86400   ; 1 day
maxretry = 5
EOF

    # Buat filter untuk HTTP GET DOS
    cat <<EOF > /etc/fail2ban/filter.d/http-get-dos.conf
[Definition]
failregex = ^<HOST> -.*"(GET|POST).*
ignoreregex =
EOF

    # Restart Fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban

 #   echo "Fail2ban diinstal dan dikonfigurasi."

    # print_success "Fail2ban"
}
function ins_epro(){
clear
print_install "Menginstall ePro WebSocket Proxy"
wget -O /usr/bin/ws "${REPO}Fls/ws" >/dev/null 2>&1
wget -O /usr/bin/tun.conf "${REPO}Cfg/tun.conf" >/dev/null 2>&1
wget -O /etc/systemd/system/ws.service "${REPO}Fls/ws.service" >/dev/null 2>&1
chmod +x /etc/systemd/system/ws.service
chmod +x /usr/bin/ws
chmod 644 /usr/bin/tun.conf
systemctl disable ws
systemctl stop ws
systemctl enable ws
systemctl start ws
systemctl restart ws
wget -q -O /usr/local/share/xray/geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" >/dev/null 2>&1
wget -q -O /usr/local/share/xray/geoip.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" >/dev/null 2>&1
wget -O /usr/sbin/ftvpn "${REPO}Fls/ftvpn" >/dev/null 2>&1
chmod +x /usr/sbin/ftvpn
iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP
iptables -A FORWARD -m string --string "announce_peer" --algo bm -j DROP
iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP
iptables -A FORWARD -m string --algo bm --string "BitTorrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "BitTorrent protocol" -j DROP
iptables -A FORWARD -m string --algo bm --string "peer_id=" -j DROP
iptables -A FORWARD -m string --algo bm --string ".torrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "announce.php?passkey=" -j DROP
iptables -A FORWARD -m string --algo bm --string "torrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "announce" -j DROP
iptables -A FORWARD -m string --algo bm --string "info_hash" -j DROP
iptables-save > /etc/iptables.up.rules
iptables-restore -t < /etc/iptables.up.rules
netfilter-persistent save
netfilter-persistent reload
cd
apt autoclean -y >/dev/null 2>&1
apt autoremove -y >/dev/null 2>&1
print_success "ePro WebSocket Proxy"
}
clear
function UDP-ZIVPN(){
clear
print_install "Menginstall UDP-ZIVPN"

CACHE_DIR="/etc/zivpn"
IP_FILE="$CACHE_DIR/ip.txt"
ISP_FILE="$CACHE_DIR/isp.txt"

mkdir -p "$CACHE_DIR"

# Ambil IP
IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com)

# Ambil ISP (tanpa AS number)
ISP=$(curl -s ipinfo.io/org | cut -d " " -f 2-10)

# Default kalau gagal
IP=${IP:-N/A}
ISP=${ISP:-N/A}

# Simpan
echo "$IP"  > "$IP_FILE"
echo "$ISP" > "$ISP_FILE"

chmod 644 "$IP_FILE" "$ISP_FILE"

echo "================================="
echo "IP  : $IP"
echo "ISP : $ISP"
echo "Saved:"
echo " - $IP_FILE"
echo " - $ISP_FILE"
echo "================================="
echo

# ─── UI Definitions ───
YELLOW='\033[1;33m'
RED='\033[0;31m'
LIGHT_BLUE='\033[1;36m'  # biru muda terang
BOLD_WHITE='\033[1;37m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
LIGHT_GREEN='\033[1;32m'
NC='\033[0m' # No Color

# ─── License Info ───
LICENSE_URL="https://raw.githubusercontent.com/ajijainalganteng-wq/izin/main/ip2"
LICENSE_INFO_FILE="/etc/zivpn/.license_info"
CONFIG_DIR="/etc/zivpn"
TELEGRAM_CONF="${CONFIG_DIR}/telegram.conf"

# ─── License Verification Function ───
function verify_license() {
    echo "Verifying installation license..."
    local SERVER_IP
    SERVER_IP=$(cat /etc/zivpn/ip.txt)
    if [ -z "$SERVER_IP" ]; then
        echo -e "${RED}Failed to retrieve server IP. Please check your internet connection.${NC}"
        exit 1
    fi

    local license_data
    license_data=$(curl -s "$LICENSE_URL")
    if [ $? -ne 0 ] || [ -z "$license_data" ]; then
        echo -e "${RED}Gagal terhubung ke server lisensi. Mohon periksa koneksi internet Anda.${NC}"
        exit 1
    fi

    local license_entry
    license_entry=$(echo "$license_data" | grep -w "$SERVER_IP")

    if [ -z "$license_entry" ]; then
        echo -e "${RED}Verifikasi Lisensi Gagal! IP Anda tidak terdaftar. IP: ${SERVER_IP}${NC}"
        exit 1
    fi

    local client_name
    local expiry_date_str
    client_name=$(echo "$license_entry" | awk '{print $1}')
    expiry_date_str=$(echo "$license_entry" | awk '{print $2}')

    local expiry_timestamp
    expiry_timestamp=$(date -d "$expiry_date_str" +%s)
    local current_timestamp
    current_timestamp=$(date +%s)

    if [ "$expiry_timestamp" -le "$current_timestamp" ]; then
        echo -e "${RED}Verifikasi Lisensi Gagal! Lisensi untuk IP ${SERVER_IP} telah kedaluwarsa. Tanggal Kedaluwarsa: ${expiry_date_str}${NC}"
        exit 1
    fi
    
    echo -e "${LIGHT_GREEN}Verifikasi Lisensi Berhasil! Client: ${client_name}, IP: ${SERVER_IP}${NC}"
    sleep 2 # Brief pause to show the message
    
    mkdir -p /etc/zivpn
    echo "CLIENT_NAME=${client_name}" > "$LICENSE_INFO_FILE"
    echo "EXPIRY_DATE=${expiry_date_str}" >> "$LICENSE_INFO_FILE"   
}
# ─── Utility Functions ───
function restart_zivpn() {
systemctl restart zivpn.service --no-block
}

verify_license
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a || true
apt -f install -y || true
apt update
apt install -y sudo screen ufw ruby rubygems figlet lolcat curl wget python3-pip jq curl sudo zip figlet lolcat vnstat cron
gem install lolcat || true

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
sudo apt install iptables-persistent -y
apt install -y iptables-persistent netfilter-persistent
sudo netfilter-persistent save

echo "1. Update OS dan install dependensi..."
apt update
apt install -y wget curl ca-certificates
update-ca-certificates

echo "2. Hentikan service lama (jika ada)..."
systemctl stop zivpn 2>/dev/null

echo "3. Hapus binary lama (jika ada)..."
rm -f /usr/local/bin/zivpn

echo "4. Download skrip resmi ZiVPN..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    FILE="zi.sh"      # amd64
    ;;
  aarch64)
    FILE="zi2.sh"       # arm64
    ;;
  armv7l|armhf)
    FILE="zi3.sh"       # arm32
    ;;
  *)
    echo "❌ Arsitektur tidak didukung: $ARCH"
    exit 1
    ;;
esac
echo "Terdeteksi arsitektur: $ARCH → pakai $FILE"
wget -O /root/zi.sh "https://raw.githubusercontent.com/arivpnstores/udp-zivpn/main/$FILE"

echo "5. Beri izin executable..."
chmod +x /root/zi.sh

echo "6. Jalankan skrip instalasi ZiVPN..."
sudo /root/zi.sh

echo "7. Reload systemd dan start service..."
systemctl daemon-reload
systemctl start zivpn
systemctl enable zivpn

echo "8. Cek status service..."
systemctl status zivpn --no-pager

echo "✅ Instalasi selesai. Service ZiVPN harusnya aktif dan panel bisa mendeteksi."

    # ─── Setting up Advanced Management ───
    echo "─── Setting up Advanced Management ───"
   
# Mendeteksi antarmuka jaringan yang aktif
ACTIVE_INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(eth|en|wlan)' | head -n 1)

# Mengecek apakah antarmuka ditemukan
if [ -z "$ACTIVE_INTERFACE" ]; then
  echo "Tidak ada antarmuka jaringan yang aktif ditemukan."
  exit 1
else
  echo "Menjalankan vnstat untuk antarmuka: $ACTIVE_INTERFACE"
  # Menjalankan vnstat untuk antarmuka yang ditemukan
  sudo vnstat -i $ACTIVE_INTERFACE
fi
echo "All dependencies are installed and up to date."

echo "Configuring vnstat for bandwidth monitoring..."
    local net_interface
    net_interface=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
    if [ -n "$net_interface" ]; then
        echo "Detected network interface: $net_interface"
        # Wait for the service to be available after installation
        sleep 2
        systemctl stop vnstat
        vnstat -u -i "$net_interface" --force
        systemctl enable vnstat
        systemctl start vnstat
        echo "vnstat setup complete for interface $net_interface."
    else
        echo "Warning: Could not automatically detect network interface for vnstat."
    fi
    
    # Download helper script from repository
    echo "Downloading helper script..."
    wget -O /usr/local/bin/zivpn_helper.sh https://raw.githubusercontent.com/arivpnstores/udp-zivpn/main/zivpn_helper.sh
    if [ $? -ne 0 ]; then
        echo "Failed to download helper script. Aborting."
        exit 1
    fi
    chmod +x /usr/local/bin/zivpn_helper.sh

    echo "Clearing initial password(s) set during base installation..."
    jq '.auth.config = []' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    touch /etc/zivpn/users.db

    RANDOM_PASS="zivpn$(shuf -i 10000-99999 -n 1)"
    EXPIRY_DATE=$(date -d "+1 day" +%s)

    echo "Creating a temporary initial account..."
    echo "${RANDOM_PASS}:${EXPIRY_DATE}" >> /etc/zivpn/users.db
    jq --arg pass "$RANDOM_PASS" '.auth.config += [$pass]' /etc/zivpn/config.json > /etc/zivpn/config.json.tmp && mv /etc/zivpn/config.json.tmp /etc/zivpn/config.json

    echo "Setting up expiry check cron job..."
    cat <<'EOF' > /etc/zivpn/expire_check.sh
#!/bin/bash
DB_FILE="/etc/zivpn/users.db"
CONFIG_FILE="/etc/zivpn/config.json"
TMP_DB_FILE="${DB_FILE}.tmp"
CURRENT_DATE=$(date +%s)
SERVICE_RESTART_NEEDED=false

if [ ! -f "$DB_FILE" ]; then exit 0; fi
> "$TMP_DB_FILE"

while IFS=':' read -r password expiry_date; do
    if [[ -z "$password" ]]; then continue; fi

    if [ "$expiry_date" -le "$CURRENT_DATE" ]; then
        echo "User '${password}' has expired. Deleting permanently."
        jq --arg pass "$password" 'del(.auth.config[] | select(. == $pass))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        SERVICE_RESTART_NEEDED=true
    else
        echo "${password}:${expiry_date}" >> "$TMP_DB_FILE"
    fi
done < "$DB_FILE"

mv "$TMP_DB_FILE" "$DB_FILE"

if [ "$SERVICE_RESTART_NEEDED" = true ]; then
    echo "Restarting zivpn service due to user removal."
    systemctl restart zivpn.service
fi
exit 0
EOF
    chmod +x /etc/zivpn/expire_check.sh
    CRON_JOB_EXPIRY="* * * * * /etc/zivpn/expire_check.sh # zivpn-expiry-check"
    (crontab -l 2>/dev/null | grep -v "# zivpn-expiry-check") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_JOB_EXPIRY") | crontab -

    echo "Setting up license check script and cron job..."
    cat <<'EOF' > /etc/zivpn/license_checker.sh
#!/bin/bash
# Zivpn License Checker
# This script is run by a cron job to periodically check the license status.

# ─── Configuration ───
LICENSE_URL="https://raw.githubusercontent.com/ajijainalganteng-wq/izin/main/ip2"
LICENSE_INFO_FILE="/etc/zivpn/.license_info"
EXPIRED_LOCK_FILE="/etc/zivpn/.expired"
TELEGRAM_CONF="/etc/zivpn/telegram.conf"
LOG_FILE="/var/log/zivpn_license.log"

# ─── Logging ───
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# ─── Helper Functions ───
function get_host() {
    local CERT_CN
    CERT_CN=$(openssl x509 -in /etc/zivpn/zivpn.crt -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' 2>/dev/null || echo "")
    if [ "$CERT_CN" == "zivpn" ] || [ -z "$CERT_CN" ]; then
        cat /etc/zivpn/ip.txt
    else
        echo "$CERT_CN"
    fi
}

function get_isp() {
    cat /etc/zivpn/isp.txt
}


# ─── Telegram Notification Function ───
send_telegram_message() {
    local message="$1"
    
    if [ ! -f "$TELEGRAM_CONF" ]; then
        log "Telegram config not found, skipping notification."
        return
    fi
    
    source "$TELEGRAM_CONF"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
        curl -s -X POST "$api_url" -d "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${message}" -d "parse_mode=Markdown" > /dev/null
        log "Simple telegram notification sent."
    else
        log "Telegram config found but token or chat ID is missing."
    fi
}

# ─── Main Logic ───
log "Starting license check..."

# 1. Get Server IP
SERVER_IP=$(cat /etc/zivpn/ip.txt)
if [ -z "$SERVER_IP" ]; then
    log "Error: Failed to retrieve server IP. Exiting."
    exit 1
fi

# 2. Get Local License Info
if [ ! -f "$LICENSE_INFO_FILE" ]; then
    log "Error: Local license info file not found. Exiting."
    exit 1
fi
source "$LICENSE_INFO_FILE" # This loads CLIENT_NAME and EXPIRY_DATE

# 3. Fetch Remote License Data
license_data=$(curl -s "$LICENSE_URL")
if [ $? -ne 0 ] || [ -z "$license_data" ]; then
    log "Error: Failed to connect to license server. Exiting."
    exit 1
fi

# 4. Check License Status from Remote
license_entry=$(echo "$license_data" | grep -w "$SERVER_IP")

if [ -z "$license_entry" ]; then
    # IP not found in remote list (Revoked)
    if [ ! -f "$EXPIRED_LOCK_FILE" ]; then
        log "License for IP ${SERVER_IP} has been REVOKED."
        systemctl stop zivpn.service
        touch "$EXPIRED_LOCK_FILE"
            MSG="Notifikasi Otomatis: Lisensi untuk Klien \`${CLIENT_NAME}\` dengan IP \`${SERVER_IP}\` telah dicabut (REVOKED). Layanan zivpn telah dihentikan."
        send_telegram_message "$MSG"
    fi
    exit 0
fi

# 5. IP Found, Check for Expiry or Renewal
client_name_remote=$(echo "$license_entry" | awk '{print $1}')
expiry_date_remote=$(echo "$license_entry" | awk '{print $2}')
expiry_timestamp_remote=$(date -d "$expiry_date_remote" +%s)
current_timestamp=$(date +%s)

# Update local license info file with the latest from server
if [ "$expiry_date_remote" != "$EXPIRY_DATE" ]; then
    log "Remote license has a different expiry date (${expiry_date_remote}). Updating local file."
    echo "CLIENT_NAME=${client_name_remote}" > "$LICENSE_INFO_FILE"
    echo "EXPIRY_DATE=${expiry_date_remote}" >> "$LICENSE_INFO_FILE"
    CLIENT_NAME=$client_name_remote
    EXPIRY_DATE=$expiry_date_remote
fi

if [ "$expiry_timestamp_remote" -le "$current_timestamp" ]; then
    # License is EXPIRED
    if [ ! -f "$EXPIRED_LOCK_FILE" ]; then
        log "License for IP ${SERVER_IP} has EXPIRED."
        systemctl stop zivpn.service
        touch "$EXPIRED_LOCK_FILE"
        host=$(get_host)
        isp=$(get_isp)
        log "Sending rich expiry notification via helper script..."
        /usr/local/bin/zivpn_helper.sh expiry-notification "$host" "$SERVER_IP" "$CLIENT_NAME" "$isp" "$EXPIRY_DATE"
    fi
else
    # License is ACTIVE (potentially renewed)
    if [ -f "$EXPIRED_LOCK_FILE" ]; then
        log "License for IP ${SERVER_IP} has been RENEWED/ACTIVATED."
        rm "$EXPIRED_LOCK_FILE"
        systemctl start zivpn.service
        host=$(get_host)
        isp=$(get_isp)
        log "Sending rich renewed notification via helper script..."
        /usr/local/bin/zivpn_helper.sh renewed-notification "$host" "$SERVER_IP" "$CLIENT_NAME" "$isp" "$expiry_timestamp_remote"
    else
        log "License is active and valid. No action needed."
    fi
fi

log "License check finished."
exit 0
EOF
    chmod +x /etc/zivpn/license_checker.sh

    CRON_JOB_LICENSE="*/5 * * * * /etc/zivpn/license_checker.sh # zivpn-license-check"
    (crontab -l 2>/dev/null | grep -v "# zivpn-license-check") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_JOB_LICENSE") | crontab -

    restart_zivpn

    # ─── API Setup ───
    echo "─── Setting up REST API Service ───"
    
    # 1. Install Node.js LTS
    if ! command -v node &> /dev/null; then
        echo "Node.js not found. Installing Node.js LTS..."
        curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
        sudo apt-get install -y nodejs
    else
        echo "Node.js is already installed."
    fi
    
    # 2. Create API directory and files
    mkdir -p /etc/zivpn/api
    
    cat <<'EOF' > /etc/zivpn/api/package.json
{
  "name": "zivpn-api",
  "version": "1.0.0",
  "description": "API for managing ZIVPN",
  "main": "api.js",
  "scripts": { "start": "node api.js" },
  "dependencies": { "express": "^4.17.1" }
}
EOF

    cat <<'EOF' > /etc/zivpn/api/api.js
const express = require('express');
const { execFile } = require('child_process');
const fs = require('fs');
const app = express();
const PORT = 5888;
const AUTH_KEY_PATH = '/etc/zivpn/api_auth.key';
const ZIVPN_MANAGER_SCRIPT = '/usr/local/bin/zivpn-manager';

const authenticate = (req, res, next) => {
    const providedAuthKey = req.query.auth;
    if (!providedAuthKey) return res.status(401).json({ status: 'error', message: 'Authentication key is required.' });

    fs.readFile(AUTH_KEY_PATH, 'utf8', (err, storedKey) => {
        if (err) return res.status(500).json({ status: 'error', message: 'Could not read authentication key.' });
        if (providedAuthKey.trim() !== storedKey.trim()) return res.status(403).json({ status: 'error', message: 'Invalid authentication key.' });
        next();
    });
};
app.use(authenticate);

const executeZivpnManager = (command, args, res) => {
    execFile('sudo', [ZIVPN_MANAGER_SCRIPT, command, ...args], (error, stdout, stderr) => {
        if (error) {
            const errorMessage = stderr.includes('Error:') ? stderr : 'An internal server error occurred.';
            return res.status(500).json({ status: 'error', message: errorMessage.trim() });
        }
        if (stdout.toLowerCase().includes('success')) {
            res.json({ status: 'success', message: stdout.trim() });
        } else {
            res.status(400).json({ status: 'error', message: stdout.trim() });
        }
    });
};

app.all('/create/zivpn', (req, res) => {
    const { password, exp } = req.query;
    if (!password || !exp) return res.status(400).json({ status: 'error', message: 'Parameters password and exp are required.' });
    executeZivpnManager('create_account', [password, exp], res);
});
app.all('/delete/zivpn', (req, res) => {
    const { password } = req.query;
    if (!password) return res.status(400).json({ status: 'error', message: 'Parameter password is required.' });
    executeZivpnManager('delete_account', [password], res);
});
app.all('/renew/zivpn', (req, res) => {
    const { password, exp } = req.query;
    if (!password || !exp) return res.status(400).json({ status: 'error', message: 'Parameters password and exp are required.' });
    executeZivpnManager('renew_account', [password, exp], res);
});
app.all('/trial/zivpn', (req, res) => {
    const { exp } = req.query;
    if (!exp) return res.status(400).json({ status: 'error', message: 'Parameter exp is required.' });
    executeZivpnManager('trial_account', [exp], res);
});

app.listen(PORT, () => console.log('ZIVPN API server running on port ' + PORT));
EOF

    # 3. Install npm dependencies
    echo "Installing API dependencies..."
    npm install --prefix /etc/zivpn/api
    
    # 4. Create and enable systemd service
    cat <<'EOF' > /etc/systemd/system/zivpn-api.service
[Unit]
Description=ZIVPN REST API Service
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn/api
ExecStart=/usr/bin/node /etc/zivpn/api/api.js
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable zivpn-api.service
    systemctl start zivpn-api.service
    
   # 5. Generate initial API key
if [ ! -f /etc/zivpn/api_auth.key ]; then
    echo "🔑 API Key belum tersedia."
    echo "Generating initial API key..."
    local initial_api_key
    initial_api_key=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 6)
    echo "$initial_api_key" > /etc/zivpn/api_auth.key
    chmod 600 /etc/zivpn/api_auth.key
    echo "✔ API Key berhasil disimpan!"
fi


    # 6. Open firewall port
    echo "Opening firewall port 5888 for API..."
    iptables -I INPUT -p tcp --dport 5888 -j ACCEPT
    
    echo "─── API Setup Complete ───"

# ==============================
# SETUP CRON (AUTO UPDATE 04:00)
# ==============================
chmod +x /usr/local/bin/update-manager
(crontab -l 2>/dev/null | grep -v "# zivpn-auto-update") | crontab -
(crontab -l 2>/dev/null; \
  echo "0 4 * * * /usr/local/bin/update-manager # zivpn-auto-update") | crontab -
echo "✅ Auto update scheduled every day at 04:00"

# ==============================
# SETUP CRON (AUTO START ZIVPN IF OFF)
# ==============================

# Hapus cron lama (kalau ada)
(crontab -l 2>/dev/null | grep -v "# zivpn-auto-start") | crontab -

# Tambahkan cron baru (cek tiap 2 menit, kalau mati → start)
(crontab -l 2>/dev/null; \
  echo "*/2 * * * * systemctl is-active --quiet zivpn || systemctl start zivpn # zivpn-auto-start") | crontab -

echo "✅ ZIVPN watchdog enabled (auto start if OFF every 2 minutes)"

    # ─── System Integration ───
echo "🔄 Updating ZiVPN Manager..."

wget -q https://raw.githubusercontent.com/arivpnstores/udp-zivpn/main/install.sh \
  -O /usr/local/bin/install.sh
chmod +x /usr/local/bin/install.sh

wget -q https://raw.githubusercontent.com/arivpnstores/udp-zivpn/main/zivpn-manager \
  -O /usr/local/bin/zivpn-manager
chmod +x /usr/local/bin/zivpn-manager

wget -q https://raw.githubusercontent.com/arivpnstores/udp-zivpn/main/zivpn_helper.sh \
  -O /usr/local/bin/zivpn_helper.sh
chmod +x /usr/local/bin/zivpn_helper.sh

wget -q https://raw.githubusercontent.com/arivpnstores/udp-zivpn/main/update.sh \
  -O /usr/local/bin/update-manager
chmod +x /usr/local/bin/update-manager

echo "🎉 ZiVPN Installer completed successfully."
}
function UDP-CUSTOM(){
clear
print_install "Menginstall UDP-CUSTOM"
cd || return 1
if ! wget -q -O udp.sh https://raw.githubusercontent.com/arivpnstores/v4/main/udp.sh; then
    print_error "Gagal download UDP-CUSTOM"
    return 1
fi
chmod +x udp.sh
if ! bash ./udp.sh; then
    print_error "Instalasi UDP-CUSTOM gagal"
    return 1
fi
print_success "UDP-CUSTOM BY RIPZZ_STORE"
}
function NOOBZVPNS() {
clear
print_install "MEMASANG NOOBZVPNS"
if ! wget -q https://raw.githubusercontent.com/arivpnstores/v4/main/noobzvpn-install.sh -O noobzvpn-install.sh; then
    print_error "Gagal download installer NoobzVPN"
    return 1
fi
chmod +x noobzvpn-install.sh
if ! bash noobzvpn-install.sh; then
    print_error "Installer NoobzVPN gagal"
    return 1
fi
systemctl restart noobzvpns 2>/dev/null || true
print_success "NOOBZVPNS BY RIPZZ_STORE"
}
function ins_restart(){
clear
print_install "Restarting All Packet"

# Modern systemd-first service handling. Missing optional services are ignored
# instead of aborting the whole installation.
local services=(nginx openvpn ssh dropbear fail2ban vnstat haproxy cron zivpn netfilter-persistent ws udp-custom noobzvpns)
systemctl daemon-reload
for svc in "${services[@]}"; do
    if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${svc}\.service"; then
        systemctl enable --now "$svc" 2>/dev/null || systemctl restart "$svc" 2>/dev/null || true
    fi
done

history -c
echo "unset HISTFILE" >> /etc/profile
cd
rm -f /root/openvpn /root/key.pem /root/cert.pem
print_success "All Packet"
}
function menuv4(){
clear
print_install "Memasang Menu Packet"
wget -O update.sh https://raw.githubusercontent.com/ajijainalganteng-wq/v4/main/update.sh 
chmod +x update.sh 
bash update.sh
}
function profile(){
clear
cat <<EOF > /root/.profile
if [ "/bin/bash" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi
mesg n || true
welcome
EOF
cat >/etc/cron.d/log_clear <<-END
		8 0 * * * root /usr/local/bin/log_clear
	END

cat >/usr/local/bin/log_clear <<-END
#!/bin/bash
tanggal=$(date +"%m-%d-%Y")
waktu=$(date +"%T")
echo "Sucsesfully clear & restart On $tanggal Time $waktu." >> /root/log-clear.txt
systemctl restart udp-custom.service
END
	chmod +x /usr/local/bin/log_clear
	
cat >/etc/cron.d/daily_backup <<-END
		0 22 * * * root /usr/local/bin/daily_backup
	END

cat >/usr/local/bin/daily_backup <<-END
#!/bin/bash
tanggal=$(date +"%m-%d-%Y")
waktu=$(date +"%T")
echo "Sucsesfully Backup On $tanggal Time $waktu." >> /root/log-backup.txt
/usr/bin/backup -r now
END
	chmod +x /usr/local/bin/daily_backup

cat >/etc/cron.d/xp <<-END
		5 0 * * * root /usr/local/bin/xp
	END

cat >/usr/local/bin/xp <<-END
#!/bin/bash
/usr/bin/expsc -r now
END
	chmod +x /usr/local/bin/xp
# Fungsi untuk menambahkan pekerjaan cron ke /etc/cron.d/
    cron_file="/etc/cron.d/auto_update"
    pekerjaan_cron="15 1 * * * root /usr/bin/auto_update"

    # Periksa apakah pekerjaan cron sudah ada di file
    if ! grep -Fq "$pekerjaan_cron" "$cron_file" 2>/dev/null; then
        echo "$pekerjaan_cron" > "$cron_file"
    fi



# Fungsi untuk menambahkan pekerjaan cron ke /etc/cron.d/
    cron_file="/etc/cron.d/backup_otomatis"
    pekerjaan_cron="15 23 * * * root /usr/bin/backupfile"

    # Periksa apakah pekerjaan cron sudah ada di file
    if ! grep -Fq "$pekerjaan_cron" "$cron_file" 2>/dev/null; then
        echo "$pekerjaan_cron" > "$cron_file"
    fi

# Fungsi untuk menambahkan pekerjaan cron ke /etc/cron.d/
    cron_file="/etc/cron.d/delete_exp"
    pekerjaan_cron="0 23 * * * root /usr/bin/xp"

    # Periksa apakah pekerjaan cron sudah ada di file
    if ! grep -Fq "$pekerjaan_cron" "$cron_file" 2>/dev/null; then
        echo "$pekerjaan_cron" > "$cron_file"
    fi
cat >/etc/cron.d/logclean <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
*/10 * * * * root /usr/bin/clearlog
END
chmod 644 /root/.profile
cat >/etc/cron.d/daily_reboot <<-END
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
5 0 * * * root /sbin/reboot
END
echo "*/1 * * * * root echo -n > /var/log/nginx/access.log" >/etc/cron.d/log.nginx
echo "*/1 * * * * root echo -n > /var/log/xray/access.log" >>/etc/cron.d/log.xray
systemctl restart cron 2>/dev/null || true
cat >/home/daily_reboot <<-END
5
END
cat >/etc/systemd/system/rc-local.service <<EOF
[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local
[Service]
Type=oneshot
ExecStart=/etc/rc.local start
RemainAfterExit=yes
TimeoutStartSec=0
[Install]
WantedBy=multi-user.target
EOF
echo "/bin/false" >>/etc/shells
echo "/usr/sbin/nologin" >>/etc/shells
cat >/etc/rc.local <<EOF
#!/bin/bash
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
systemctl restart netfilter-persistent
exit 0
EOF
chmod +x /etc/rc.local
AUTOREB=$(cat /home/daily_reboot)
SETT=11
if [ $AUTOREB -gt $SETT ]; then
TIME_DATE="PM"
else
TIME_DATE="AM"
fi
print_success "Menu Packet"
}
function enable_services(){
clear
print_install "Enable Service"
systemctl daemon-reload
systemctl start netfilter-persistent
systemctl enable --now rc-local
systemctl enable --now cron
systemctl enable --now netfilter-persistent
systemctl restart nginx
systemctl restart xray
systemctl restart cron
systemctl restart haproxy
print_success "Enable Service"
clear
}
function instal(){
clear
print_install "Menginstall first_setup"
first_setup
clear
print_install "Menginstall nginx"
nginx_install
clear
print_install "Menginstall folder_xray"
make_folder_xray
clear
print_install "Menginstall pasang_ssl"
pasang_ssl
clear
print_install "Menginstall xray"
install_xray
clear
print_install "Menginstall ssh"
ssh
clear
#print_install "Menginstall UDP-ZIVPN"
#UDP-ZIVPN
clear
print_install "Menginstall UDP-CUSTOM"
UDP-CUSTOM
clear
print_install "Menginstall NOOBZVPNS"
NOOBZVPNS
clear
print_install "Menginstall udp_mini"
udp_mini
clear
print_install "Menginstall ssh_slow"
ssh_slow
clear
print_install "Menginstall SSHD"
ins_SSHD
clear
print_install "Menginstall dropbear"
ins_dropbear
clear
print_install "Menginstall vnstat"
ins_vnstat
clear
print_install "Menginstall openvpn"
ins_openvpn
clear
print_install "Menginstall backup"
ins_backup
clear
print_install "Menginstall swab"
ins_swab
clear
print_install "Menginstall Fail2ban"
ins_Fail2ban
clear
print_install "Menginstall epro"
ins_epro
clear
print_install "Menginstall restart"
ins_restart
clear
print_install "Menginstall menu"
menuv4
clear
print_install "Menginstall profile"
profile
clear
print_install "enable_services"
enable_services
clear
print_install "restart_system"
restart_system
clear
print_install "auto_system"
auto_system
clear
}
instal
echo ""
NET_IFACE="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1)"
if [ -n "$NET_IFACE" ] && command -v iptables >/dev/null 2>&1; then
    iptables -t nat -A PREROUTING -i "$NET_IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 || true
fi
netfilter-persistent save
netfilter-persistent reload

# FINAL VALIDATION - never print success while a critical service/config is broken.
/usr/local/bin/xray run -test -config /etc/xray/config.json >/dev/null 2>&1 || { print_error "Final Xray config test gagal."; exit 1; }
nginx -t >/dev/null 2>&1 || { print_error "Final nginx config test gagal."; exit 1; }
haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1 || { print_error "Final HAProxy config test gagal."; exit 1; }
sshd -t || { print_error "Final SSH config test gagal."; exit 1; }
for svc in xray nginx haproxy ssh; do
    systemctl is-active --quiet "$svc" || { print_error "Service critical $svc tidak aktif."; exit 1; }
done
history -c
rm -rf /root/install
rm -rf /root/menu
rm -rf /root/*.zip
rm -rf /root/*.sh
rm -rf /root/LICENSE
rm -rf /root/README.md
rm -rf /root/domain
secs_to_human "$(($(date +%s) - ${start}))"
sudo hostnamectl set-hostname $username
if wget -q https://raw.githubusercontent.com/arivpnstores/api-ari/main/api.sh -O /tmp/ripzz-api.sh; then
    chmod +x /tmp/ripzz-api.sh
    bash /tmp/ripzz-api.sh || print_error "API tambahan gagal dipasang; instalasi utama tetap selesai."
    rm -f /tmp/ripzz-api.sh
else
    print_error "API tambahan tidak dapat diunduh; dilewati."
fi
clear
echo -e "\033[96m==========================\033[0m"
echo -e "\033[92m      INSTALL SUCCES      \033[0m"
echo -e "\033[96m==========================\033[0m"
echo -e ""
read -n 1 -s -r -p "Press any key to back on menu"
menu
rm -rf /root/install
