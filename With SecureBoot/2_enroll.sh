#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

MOK_PASSWORD="12345678"
MOK_DIR="/var/lib/shim-signed/mok"
KERNEL_VER="$(uname -r)"
TARGET_VMLINUZ="/boot/vmlinuz-${KERNEL_VER}"

echo "=========================================================="
echo " STEP 2: MOK Key Setup, Reset, and Kernel Signing"
echo " Secure Boot State: Must be OFF for this step"
echo "=========================================================="

apt-get update -qq && apt-get install -y mokutil openssl sbsigntool shim-signed grub-efi-amd64-signed

rm -rf "$MOK_DIR"
mkdir -p "$MOK_DIR"

echo "[✓] Generating fresh MOK keypair..."
openssl req -new -x509 -nodes -days 36500 \
    -subj "/CN=MediaTek MT7927 Local Signing Key/" \
    -outform DER -out "$MOK_DIR/MOK.der" -keyout "$MOK_DIR/MOK.priv" &>/dev/null
openssl x509 -inform DER -in "$MOK_DIR/MOK.der" -outform PEM -out "$MOK_DIR/MOK.pem"

if [[ -f "$TARGET_VMLINUZ" ]]; then
    echo "[✓] Signing kernel image ${TARGET_VMLINUZ}..."
    sbsign --key "$MOK_DIR/MOK.priv" --cert "$MOK_DIR/MOK.pem" \
        --output "$TARGET_VMLINUZ" "$TARGET_VMLINUZ" || true
fi

echo "[✓] Triggering clean MOK reset and queueing import..."
printf "%s\n%s\n" "${MOK_PASSWORD}" "${MOK_PASSWORD}" | mokutil --reset || true
printf "%s\n%s\n" "${MOK_PASSWORD}" "${MOK_PASSWORD}" | mokutil --import "$MOK_DIR/MOK.der" || true

echo
echo "=========================================================="
echo " ACTION REQUIRED:"
echo " 1. Reboot your computer for a 2nd time."
echo " 2. Go into your BIOS/UEFI and TURN SECURE BOOT BACK ON."
echo " 3. On reboot, a blue MOK screen will appear."
echo "    - Select 'Enroll MOK' / 'Continue'"
echo "    - enter password: "${MOK_PASSWORD}""
echo " 4. Once back in Ubuntu, run script '3_finalize.sh'."
echo "=========================================================="

read -rp "Press Enter to exit..."
