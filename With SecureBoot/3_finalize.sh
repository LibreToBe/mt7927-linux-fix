#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi

MODULE="mt7925e"
VERSION="2.9"
KERNEL_VER="$(uname -r)"
MOK_DIR="/var/lib/shim-signed/mok"

echo "=========================================================="
echo " STEP 3: Firmware Deployment, Driver Activation & Signing Hook"
echo " Secure Boot State: Must be ON"
echo "=========================================================="

apt-get update -qq && apt-get install -y git curl wget iw tar gzip sbsigntool

# [1/3] Setup Automated Kernel Signing Hook (Fixes In-Place Fragility)
echo "[✓] Setting up automated kernel signing hook for future updates..."
mkdir -p /etc/kernel/postinst.d
cat << 'EOF' > /etc/kernel/postinst.d/zz-sbsign
#!/usr/bin/env bash
set -e

MOK_PRIV="/var/lib/shim-signed/mok/MOK.priv"
MOK_CERT="/var/lib/shim-signed/mok/MOK.pem"

KERNEL_VERSION="$1"
VMLINUZ_PATH="/boot/vmlinuz-${KERNEL_VERSION}"

if [[ -f "$MOK_PRIV" && -f "$MOK_CERT" && -f "$VMLINUZ_PATH" ]]; then
    echo "==> Automatically signing kernel ${KERNEL_VERSION} for Secure Boot..."
    sbsign --key "$MOK_PRIV" --cert "$MOK_CERT" --output "$VMLINUZ_PATH" "$VMLINUZ_PATH"
    echo "==> Successfully signed /boot/vmlinuz-${KERNEL_VERSION}"
fi
EOF
chmod +x /etc/kernel/postinst.d/zz-sbsign

# [2/3] Firmware Deployment for MT7927
echo "[✓] Downloading and deploying MT7927 firmware binaries..."
FIRMWARE_DIR="/lib/firmware/mediatek/mt7927"
mkdir -p "${FIRMWARE_DIR}"
mkdir -p "/lib/firmware/mediatek"

BASE_FW_URL="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7927"
GITLAB_BT_URL="https://gitlab.com/jetm/linux-firmware/-/raw/77ad2a92acf2ac3e5ea47432b43d925ff99db909/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin"

FW_WIFI_FILES=(
    "WIFI_RAM_CODE_MT6639_2_1.bin"
    "WIFI_MT6639_PATCH_MCU_2_1_hdr.bin"
)

for fw in "${FW_WIFI_FILES[@]}"; do
    curl -sLo "/lib/firmware/mediatek/${fw}" "${BASE_FW_URL}/${fw}" || true
    cp -f "/lib/firmware/mediatek/${fw}" "${FIRMWARE_DIR}/${fw}" 2>/dev/null || true
done
curl -sLo "/lib/firmware/mediatek/BT_RAM_CODE_MT6639_2_1_hdr.bin" "${GITLAB_BT_URL}" || true
cp -f "/lib/firmware/mediatek/BT_RAM_CODE_MT6639_2_1_hdr.bin" "${FIRMWARE_DIR}/BT_RAM_CODE_MT6639_2_1_hdr.bin" 2>/dev/null || true

# [3/3] Power & Regulatory Tweaks
echo "options ${MODULE} disable_aspm=1" > /etc/modprobe.d/mt7925e.conf
mkdir -p /etc/NetworkManager/conf.d/
echo -e "[connection]\nwifi.powersave = 2" > /etc/NetworkManager/conf.d/disable-powersave.conf
iw reg set "US" || true

# Reload Modules
modprobe -r "${MODULE}" btusb btmtk 2>/dev/null || true
sleep 1
modprobe "${MODULE}" || true
modprobe btmtk || true
modprobe btusb || true

echo "=========================================================="
echo " [✓] SETUP COMPLETE WITH SECURE BOOT ACTIVE!"
echo "=========================================================="
if lsmod | grep -q "^${MODULE}"; then
    echo " [✓] Success: ${MODULE} driver is active and running!"
else
    echo " [!] Note: Please restart your computer once more to initialize hardware."
fi

read -rp "Press Enter to exit..."
