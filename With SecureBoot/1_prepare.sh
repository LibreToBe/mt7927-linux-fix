#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

echo "=========================================================="
echo " STEP 1: Kernel Preparation & 7.2+ Upgrade"
echo " Secure Boot State: Can be ON or OFF"
echo "=========================================================="

MIN_KERNEL_CODE=7002
KERNEL_VER="$(uname -r)"
KERNEL_MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VER" | cut -d. -f2)
KERNEL_CODE=$(( KERNEL_MAJOR * 1000 + KERNEL_MINOR ))

find_installed_kernel_ge() {
    local min_code=$1 best="" best_code=0 img v maj min code
    for img in /boot/vmlinuz-*; do
        [[ -e "$img" ]] || continue
        v=$(basename "$img" | sed 's/^vmlinuz-//')
        maj=$(echo "$v" | cut -d. -f1)
        min=$(echo "$v" | cut -d. -f2)
        [[ "$maj" =~ ^[0-9]+$ && "$min" =~ ^[0-9]+$ ]] || continue
        code=$(( maj * 1000 + min ))
        if [[ $code -ge $min_code && $code -gt $best_code ]]; then
            best="$v"
            best_code=$code
        fi
    done
    echo "$best"
}

if [[ $KERNEL_CODE -lt $MIN_KERNEL_CODE ]]; then
    ALREADY_INSTALLED=$(find_installed_kernel_ge "$MIN_KERNEL_CODE")
    if [[ -z "$ALREADY_INSTALLED" ]]; then
        echo "[✓] Installing mainline PPA to fetch kernel >= 7.2..."
        apt-get update -qq && apt-get install -y software-properties-common
        add-apt-repository -y ppa:cappelikan/ppa
        apt-get update -qq && apt-get install -y mainline
        mainline install-latest || true
        ALREADY_INSTALLED=$(find_installed_kernel_ge "$MIN_KERNEL_CODE")
    fi
    
    echo
    echo "=========================================================="
    echo " ACTION REQUIRED:"
    echo " 1. Reboot your computer."
    echo " 2. Go into your BIOS/UEFI and TURN SECURE BOOT OFF."
    echo " 3. Select kernel ${ALREADY_INSTALLED} at the GRUB boot menu."
    echo " 4. Run script '2_enroll.sh' after reboot."
    echo "=========================================================="
else
    echo "[✓] Already running a compatible kernel (>= 7.2)."
    echo " You can proceed directly to running '2_enroll.sh'."
fi

read -rp "Press Enter to exit..."
