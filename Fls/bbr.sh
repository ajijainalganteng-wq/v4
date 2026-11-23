
#!/bin/bash
# =========================================
# Edition : BBR Stable Edition V4.0
# Author  : RIPZZ STORE
# TCP BBR : Official Linux Kernel
# Support : Ubuntu / Debian-based systems
# =========================================

red='\e[1;31m'
green='\e[0;32m'
purple='\e[0;35m'
orange='\e[0;33m'
NC='\e[0m'

BBR_CONF="/etc/sysctl.d/99-ripzz-bbr.conf"
MODULE_CONF="/etc/modules-load.d/99-ripzz-bbr.conf"

clear

echo ""
echo -e "${green}Installing Official TCP BBR${NC}"
echo -e "${purple}RIPZZ STORE - Stable Edition V4.0${NC}"
echo ""

# =========================================
# ROOT CHECK
# =========================================

if [[ "$EUID" -ne 0 ]]; then
    echo -e "${red}Error: Please run this script as root.${NC}"
    exit 1
fi

# =========================================
# CHECK REQUIRED COMMANDS
# =========================================

for cmd in sysctl modprobe awk grep cp install; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${red}Missing required command: $cmd${NC}"
        exit 1
    fi
done

# =========================================
# BACKUP CONFIGURATION
# =========================================

BACKUP_DIR="/root/bbr-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$BACKUP_DIR"

for file in "$BBR_CONF" "$MODULE_CONF"; do
    if [[ -f "$file" ]]; then
        cp -a "$file" "$BACKUP_DIR/"
    fi
done

# =========================================
# CHECK BBR SUPPORT
# =========================================

Check_BBR() {
    local available

    available="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)"

    echo "$available" | tr ' ' '\n' | grep -qx "bbr"
}

# =========================================
# INSTALL BBR
# =========================================

Install_BBR() {

    echo -e "${green}================================${NC}"
    echo -e "${green}Checking TCP BBR Support...${NC}"

    echo "Kernel Version: $(uname -r)"

    # Try loading official kernel module
    modprobe tcp_bbr 2>/dev/null || true

    # Check BBR availability
    if ! Check_BBR; then
        echo -e "${red}BBR is not supported by this kernel.${NC}"
        echo -e "${orange}Please install a supported Ubuntu kernel.${NC}"
        return 1
    fi

    echo -e "${green}TCP BBR is supported.${NC}"

    # Load module automatically at boot if modular
    if modinfo tcp_bbr >/dev/null 2>&1; then
        install -d -m 755 /etc/modules-load.d
        echo "tcp_bbr" > "$MODULE_CONF"
        chmod 644 "$MODULE_CONF"
    else
        rm -f "$MODULE_CONF"
    fi

    echo -e "${green}BBR module configuration completed.${NC}"

    # =====================================
    # CHECK FQ SUPPORT
    # =====================================

    local use_fq=0

    if modprobe sch_fq 2>/dev/null || [[ -d /sys/module/sch_fq ]]; then
        use_fq=1
    fi

    # =====================================
    # WRITE OFFICIAL BBR CONFIGURATION
    # =====================================

    install -d -m 755 /etc/sysctl.d

    if [[ "$use_fq" -eq 1 ]]; then

        cat > "$BBR_CONF" <<EOF
# RIPZZ STORE - Official TCP BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    else

        echo "net.ipv4.tcp_congestion_control = bbr" > "$BBR_CONF"

        echo -e "${orange}FQ is unavailable. Using BBR without FQ.${NC}"

    fi

    chmod 644 "$BBR_CONF"

    # =====================================
    # APPLY CONFIGURATION
    # =====================================

    if ! sysctl -p "$BBR_CONF" >/dev/null 2>&1; then

        echo -e "${orange}FQ configuration failed. Retrying BBR only.${NC}"

        cat > "$BBR_CONF" <<EOF
# RIPZZ STORE - Official TCP BBR
net.ipv4.tcp_congestion_control = bbr
EOF

        if ! sysctl -p "$BBR_CONF" >/dev/null 2>&1; then
            echo -e "${red}Failed to apply BBR configuration.${NC}"
            return 1
        fi

    fi

    # =====================================
    # VERIFY BBR
    # =====================================

    local current

    current="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"

    if [[ "$current" == "bbr" ]] && Check_BBR; then

        echo -e "${green}TCP BBR Installation Successful!${NC}"

    else

        echo -e "${red}TCP BBR verification failed.${NC}"
        return 1

    fi

    echo -e "${green}================================${NC}"

    return 0
}

# =========================================
# OPTIMIZE PARAMETERS
# =========================================

Optimize_Parameters() {

    echo -e "${green}================================${NC}"
    echo -e "${green}Checking Network Configuration...${NC}"

    # =====================================
    # CHECK TCP BBR
    # =====================================

    if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" != "bbr" ]]; then
        echo -e "${red}BBR is not active. Optimization cancelled.${NC}"
        return 1
    fi

    # =====================================
    # VERIFY FQ
    # =====================================

    local qdisc

    qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null)"

    if [[ "$qdisc" == "fq" ]]; then
        echo -e "${green}FQ Queue Discipline: Active${NC}"
    else
        echo -e "${orange}FQ Queue Discipline: Not Active${NC}"
    fi

    # =====================================
    # VERIFY PERSISTENT CONFIGURATION
    # =====================================

    if [[ ! -s "$BBR_CONF" ]]; then
        echo -e "${red}BBR configuration file is missing.${NC}"
        return 1
    fi

    echo -e "${green}Persistent configuration verified.${NC}"

    echo -e "${green}================================${NC}"

    return 0
}

# =========================================
# MAIN INSTALLATION
# =========================================

if ! Install_BBR; then
    echo ""
    echo -e "${red}BBR Installation Failed!${NC}"
    echo -e "${orange}Backup: $BACKUP_DIR${NC}"
    exit 1
fi

if ! Optimize_Parameters; then
    echo -e "${red}BBR Optimization Verification Failed!${NC}"
    exit 1
fi

# =========================================
# FINAL STATUS
# =========================================

echo ""
echo -e "${green}================================================${NC}"
echo -e "${green}       OFFICIAL TCP BBR INSTALLATION SUCCESS     ${NC}"
echo -e "${green}================================================${NC}"

echo ""
echo -e "${purple}Kernel Version:${NC} $(uname -r)"
echo -e "${purple}Congestion Control:${NC} $(sysctl -n net.ipv4.tcp_congestion_control)"
echo -e "${purple}Default Qdisc:${NC} $(sysctl -n net.core.default_qdisc)"
echo -e "${purple}Backup Directory:${NC} $BACKUP_DIR"

echo ""
echo -e "${green}BBR is configured for automatic startup.${NC}"
echo ""

exit 0
