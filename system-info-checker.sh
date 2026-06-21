#!/usr/bin/env bash
#
# sysinfo.sh - Interactive system stats checker for Linux Mint / Ubuntu
# Prompts you for what to inspect. Checks for missing tools and offers to install them.
#
# Usage:  chmod +x sysinfo.sh  &&  ./sysinfo.sh
#

set -o pipefail

# ---------- colors ----------
BOLD=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'
YLW=$'\e[33m'; BLU=$'\e[34m'; CYN=$'\e[36m'; RST=$'\e[0m'

pause() { echo; read -rp "${DIM}Press Enter to return to the menu...${RST}"; }
hdr()   { echo; echo "${BOLD}${BLU}=== $1 ===${RST}"; }

# ---------- tool/install handling ----------
# Map a command to the apt package that provides it (when they differ).
pkg_for() {
    case "$1" in
        sensors)       echo "lm-sensors" ;;
        smartctl)      echo "smartmontools" ;;
        nvme)          echo "nvme-cli" ;;
        glxinfo)       echo "mesa-utils" ;;
        inxi)          echo "inxi" ;;
        btop)          echo "btop" ;;
        htop)          echo "htop" ;;
        iotop)         echo "iotop" ;;
        nethogs)       echo "nethogs" ;;
        hdparm)        echo "hdparm" ;;
        duf)           echo "duf" ;;
        dmidecode)     echo "dmidecode" ;;
        lshw)          echo "lshw" ;;
        speedtest-cli) echo "speedtest-cli" ;;
        *)             echo "$1" ;;
    esac
}

# Every package this script can make use of.
ALL_PKGS=(lm-sensors smartmontools nvme-cli mesa-utils inxi btop htop \
          iotop nethogs hdparm duf dmidecode lshw hwinfo speedtest-cli)

# Install everything in one go.
install_all() {
    echo "${BOLD}${BLU}Installing all supported tools...${RST}"
    echo "${DIM}Packages: ${ALL_PKGS[*]}${RST}"
    echo
    sudo apt update && sudo apt install -y "${ALL_PKGS[@]}"
    local rc=$?
    echo
    if [[ $rc -eq 0 ]]; then
        echo "${GRN}All packages installed.${RST}"
        echo "${YLW}Tip: run 'sudo sensors-detect' once to enable temperature readings.${RST}"
    else
        echo "${RED}apt finished with errors (exit $rc).${RST}"
    fi
    return $rc
}

# Ensure a command exists; offer to install it if not. Returns 0 if usable.
need() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi
    local pkg; pkg="$(pkg_for "$cmd")"
    echo "${YLW}'$cmd' is not installed${RST} (package: ${BOLD}$pkg${RST})."
    read -rp "Install it now with apt? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        sudo apt update && sudo apt install -y "$pkg"
        command -v "$cmd" >/dev/null 2>&1 && return 0
    fi
    echo "${RED}Skipping (tool unavailable).${RST}"
    return 1
}

# Pick a disk device interactively for disk-specific commands.
pick_disk() {
    echo "${DIM}Available block devices:${RST}"
    lsblk -d -o NAME,SIZE,MODEL | sed 's/^/   /'
    echo
    read -rp "Enter device (e.g. sda or nvme0n1) [sda]: " dev
    dev="${dev:-sda}"
    echo "/dev/$dev"
}

# ---------- check functions ----------
check_cpu() {
    hdr "CPU"
    lscpu
    echo; echo "${CYN}Live core clocks (Ctrl-C to stop):${RST}"
    read -rp "Show live clock speeds? [y/N] " a
    [[ "$a" =~ ^[Yy]$ ]] && watch -n1 "grep 'MHz' /proc/cpuinfo"
    pause
}

check_temps() {
    hdr "Temperatures / Sensors"
    if need sensors; then
        if ! sensors 2>/dev/null | grep -q .; then
            echo "${YLW}No sensors configured. Run: ${BOLD}sudo sensors-detect${RST}"
            read -rp "Run sensors-detect now? [y/N] " a
            [[ "$a" =~ ^[Yy]$ ]] && sudo sensors-detect
        fi
        sensors
    fi
    pause
}

check_memory() {
    hdr "Memory / RAM"
    free -h
    echo
    read -rp "Show physical RAM stick details (needs sudo)? [y/N] " a
    if [[ "$a" =~ ^[Yy]$ ]] && need dmidecode; then
        sudo dmidecode -t memory | grep -E 'Size|Speed|Type:|Manufacturer|Locator:' | grep -v 'Unknown\|No Module'
    fi
    pause
}

check_disk_health() {
    hdr "Disk Health (SMART)"
    need smartctl || { pause; return; }
    local d; d="$(pick_disk)"
    if [[ "$d" == *nvme* ]] && need nvme; then
        sudo nvme smart-log "$d"
    else
        sudo smartctl -H "$d"
        echo
        read -rp "Show full SMART attributes? [y/N] " a
        [[ "$a" =~ ^[Yy]$ ]] && sudo smartctl -a "$d"
    fi
    pause
}

check_disk_usage() {
    hdr "Disk Usage & Layout"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,MODEL
    echo
    if command -v duf >/dev/null 2>&1; then duf; else df -h; fi
    pause
}

check_disk_speed() {
    hdr "Disk Speed Benchmark"
    need hdparm || { pause; return; }
    local d; d="$(pick_disk)"
    echo "${DIM}Running buffered + cached read test...${RST}"
    sudo hdparm -tT "$d"
    pause
}

check_gpu() {
    hdr "GPU"
    lspci | grep -i 'vga\|3d\|display'
    echo
    if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi; fi
    read -rp "Show OpenGL renderer info? [y/N] " a
    if [[ "$a" =~ ^[Yy]$ ]] && need glxinfo; then
        glxinfo | grep -E 'OpenGL vendor|OpenGL renderer|OpenGL version'
    fi
    pause
}

check_board() {
    hdr "Motherboard / BIOS"
    need dmidecode || { pause; return; }
    echo "${CYN}Baseboard:${RST}";  sudo dmidecode -t baseboard | grep -E 'Manufacturer|Product Name|Version'
    echo "${CYN}BIOS:${RST}";       sudo dmidecode -t bios      | grep -E 'Vendor|Version|Release Date'
    pause
}

check_summary() {
    hdr "Full System Summary"
    if need inxi; then inxi -Fxz; else
        need lshw && sudo lshw -short
    fi
    pause
}

check_network() {
    hdr "Network"
    ip -brief a
    echo
    read -rp "Run internet speed test? [y/N] " a
    if [[ "$a" =~ ^[Yy]$ ]] && need speedtest-cli; then speedtest-cli; fi
    pause
}

check_monitor() {
    hdr "Live Monitor"
    if command -v btop >/dev/null 2>&1; then btop
    elif command -v htop >/dev/null 2>&1; then htop
    else
        need btop && btop || { need htop && htop; }
    fi
}

save_report() {
    hdr "Save Full Report to File"
    local out="$HOME/sysinfo_report_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "===== SYSTEM REPORT $(date) ====="
        echo; echo "----- CPU -----";        lscpu
        echo; echo "----- MEMORY -----";     free -h
        echo; echo "----- DISKS -----";      lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,MODEL; df -h
        echo; echo "----- GPU -----";        lspci | grep -i 'vga\|3d\|display'
        if command -v inxi >/dev/null 2>&1; then
            echo; echo "----- INXI -----";   inxi -Fxz
        fi
        if command -v sensors >/dev/null 2>&1; then
            echo; echo "----- SENSORS -----"; sensors
        fi
    } | tee "$out"
    echo; echo "${GRN}Saved to: $out${RST}"
    pause
}

# ---------- menu ----------
menu() {
    clear
    echo "${BOLD}${GRN}"
    echo "  ┌───────────────────────────────────────────┐"
    echo "  │        SYSTEM STATS CHECKER (Mint)         │"
    echo "  └───────────────────────────────────────────┘"
    echo "${RST}"
    echo "   ${BOLD}1)${RST} CPU info"
    echo "   ${BOLD}2)${RST} Temperatures / sensors"
    echo "   ${BOLD}3)${RST} Memory / RAM"
    echo "   ${BOLD}4)${RST} Disk health (SMART)"
    echo "   ${BOLD}5)${RST} Disk usage & layout"
    echo "   ${BOLD}6)${RST} Disk speed benchmark"
    echo "   ${BOLD}7)${RST} GPU info"
    echo "   ${BOLD}8)${RST} Motherboard / BIOS"
    echo "   ${BOLD}9)${RST} Full system summary (inxi)"
    echo "  ${BOLD}10)${RST} Network"
    echo "  ${BOLD}11)${RST} Live monitor (btop/htop)"
    echo "  ${BOLD}12)${RST} Save full report to file"
    echo "   ${BOLD}a)${RST} Run ALL read-only checks"
    echo "   ${BOLD}i)${RST} Install ALL tools"
    echo "   ${BOLD}q)${RST} Quit"
    echo
    read -rp "  ${CYN}Choose an option:${RST} " choice
}

run_all() {
    check_cpu; check_memory; check_disk_usage; check_gpu; check_board; check_summary; check_network
}

# ---------- command-line flags ----------
usage() {
    cat <<EOF
${BOLD}sysinfo.sh${RST} - interactive system stats checker

Usage: ./sysinfo.sh [OPTION]

  ${BOLD}-i, --install${RST}    Install all supported tools, then exit
  ${BOLD}-h, --help${RST}       Show this help and exit

With no option, launches the interactive menu.
EOF
}

case "${1:-}" in
    -i|--install) install_all; exit $? ;;
    -h|--help)    usage; exit 0 ;;
    "")           ;;  # no args -> fall through to menu
    *)            echo "${RED}Unknown option: $1${RST}"; echo; usage; exit 1 ;;
esac

# ---------- main loop ----------
while true; do
    menu
    case "$choice" in
        1)  check_cpu ;;
        2)  check_temps ;;
        3)  check_memory ;;
        4)  check_disk_health ;;
        5)  check_disk_usage ;;
        6)  check_disk_speed ;;
        7)  check_gpu ;;
        8)  check_board ;;
        9)  check_summary ;;
        10) check_network ;;
        11) check_monitor ;;
        12) save_report ;;
        a|A) run_all ;;
        i|I) install_all; pause ;;
        q|Q) echo "Bye."; exit 0 ;;
        *)  echo "${RED}Invalid option.${RST}"; sleep 1 ;;
    esac
done
