#!/usr/bin/env bash
set -euo pipefail

MODULE="mediatek-mt7927"
VERSION="2.9"
TARGET_SRC="/usr/src/${MODULE}-${VERSION}"
ARCHIVE_NAME="${MODULE}-dkms-${VERSION}.tar.gz"
FIRMWARE_DIR="/lib/firmware/mediatek/mt7927"
REG_DOMAIN="US"

TMP_CLONE=""

cleanup() {
    local exit_code=$?
    if [[ -n "${TMP_CLONE:-}" && -d "${TMP_CLONE}" ]]; then
        rm -rf "${TMP_CLONE}"
    fi
    if [[ $exit_code -ne 0 ]]; then
        echo
        echo "=========================================================="
        echo "[✗] ERROR: Script failed unexpectedly (exit code: $exit_code)."
        echo "=========================================================="
        read -rp "Press Enter to exit..."
    fi
}
trap cleanup EXIT INT TERM

# 1. Auto-spawn terminal window if double-clicked from file manager
if ! tty -s; then
    if command -v gnome-terminal &>/dev/null; then
        exec gnome-terminal -- bash "$0" "$@"
    elif command -v x-terminal-emulator &>/dev/null; then
        exec x-terminal-emulator -e bash "$0" "$@"
    elif command -v xterm &>/dev/null; then
        exec xterm -e bash "$0" "$@"
    fi
fi

# 2. Auto-elevate privileges via pkexec if not root
if [[ $EUID -ne 0 ]]; then
    if command -v pkexec &>/dev/null; then
        exec pkexec "$0" "$@"
    else
        echo "[✗] Root privileges required. Run with sudo."
        read -rp "Press Enter to exit..."
        exit 1
    fi
fi

echo "=========================================================="
echo " MediaTek MT7927 Wi-Fi 7 & Bluetooth Setup & Diagnostics "
echo "=========================================================="
echo

# [1/7] Kernel Check
KERNEL_VER="$(uname -r)"
KERNEL_MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VER" | cut -d. -f2)

USE_NATIVE_DRIVER=0
if [[ "$KERNEL_MAJOR" -gt 7 ]] || [[ "$KERNEL_MAJOR" -eq 7 && "$KERNEL_MINOR" -ge 1 ]]; then
    echo "[✓] Kernel Version: ${KERNEL_VER} (Using native in-tree drivers)"
    USE_NATIVE_DRIVER=1
else
    echo "[✓] Kernel Version: ${KERNEL_VER} (Kernel < 7.1 requires DKMS driver)"
fi

# [2/7] Dependencies Check & Install
REQUIRED_DEPS=(curl wget iw)
if [[ $USE_NATIVE_DRIVER -eq 0 ]]; then
    REQUIRED_DEPS+=(dkms gcc make tar gzip git "linux-headers-${KERNEL_VER}")
fi

MISSING_DEPS=()
for dep in "${REQUIRED_DEPS[@]}"; do
    if ! dpkg -l "$dep" &>/dev/null && ! command -v "$dep" &>/dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo "[!] Installing missing dependencies: ${MISSING_DEPS[*]}..."
    apt-get update -qq
    apt-get install -y -qq "${MISSING_DEPS[@]}" > /dev/null
    echo "[✓] Dependencies installed"
else
    echo "[✓] Dependencies: All host packages satisfied"
fi

# [3/7 & 4/7 & 5/7] DKMS Module Build & Install
if [[ $USE_NATIVE_DRIVER -eq 1 ]]; then
    echo "[✓] DKMS Compilation: Skipped (Kernel >= 7.1 native driver active)"
else
    echo "[!] Locating driver source package..."
    ARCHIVE_PATH=""

    SEARCH_LOCS=(
        "$(pwd)/${ARCHIVE_NAME}"
        "$HOME/${ARCHIVE_NAME}"
        "/tmp/${ARCHIVE_NAME}"
    )

    for loc in "${SEARCH_LOCS[@]}"; do
        if [[ -f "$loc" ]]; then
            ARCHIVE_PATH="$loc"
            break
        fi
    done

    mkdir -p "$TARGET_SRC"

    if [[ -n "$ARCHIVE_PATH" ]]; then
        tar -xzf "$ARCHIVE_PATH" -C "$TARGET_SRC" --strip-components=1
    else
        TMP_CLONE=$(mktemp -d)
        git clone --quiet --depth 1 https://github.com/openwrt/mt76 "$TMP_CLONE"
        cp -a "$TMP_CLONE"/. "$TARGET_SRC"/

        if [[ ! -f "$TARGET_SRC/dkms.conf" ]]; then
            cat > "$TARGET_SRC/dkms.conf" <<EOF
PACKAGE_NAME="${MODULE}"
PACKAGE_VERSION="${VERSION}"
BUILT_MODULE_NAME[0]="mt7925e"
DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless/mediatek/mt76/mt7925"
AUTOINSTALL="yes"
EOF
        fi
    fi

    if dkms status 2>/dev/null | grep -q "${MODULE}/${VERSION}"; then
        dkms remove -m "$MODULE" -v "$VERSION" --all || true
    fi

    dkms add -m "$MODULE" -v "$VERSION" --force > /dev/null
    dkms build -m "$MODULE" -v "$VERSION" -k "${KERNEL_VER}" > /dev/null
    dkms install -m "$MODULE" -v "$VERSION" -k "${KERNEL_VER}" --force > /dev/null
    depmod -a
    echo "[✓] DKMS Driver Module: Compiled and installed (${MODULE}-${VERSION})"
fi

# [6/7] Verify / Fetch MediaTek MT7927 Firmware
mkdir -p "${FIRMWARE_DIR}"

BASE_FW_URL="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/mediatek/mt7927"
GITLAB_BT_URL="https://gitlab.com/jetm/linux-firmware/-/raw/77ad2a92acf2ac3e5ea47432b43d925ff99db909/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin"

FW_WIFI_FILES=(
    "WIFI_RAM_CODE_MT6639_2_1.bin"
    "WIFI_MT6639_PATCH_MCU_2_1_hdr.bin"
)

FW_MISSING=0
for fw in "${FW_WIFI_FILES[@]}"; do
    if [[ ! -f "${FIRMWARE_DIR}/${fw}" ]]; then
        curl -sLo "${FIRMWARE_DIR}/${fw}" "${BASE_FW_URL}/${fw}" || FW_MISSING=1
    fi
done

if [[ ! -f "${FIRMWARE_DIR}/BT_RAM_CODE_MT6639_2_1_hdr.bin" ]]; then
    curl -sLo "${FIRMWARE_DIR}/BT_RAM_CODE_MT6639_2_1_hdr.bin" "${GITLAB_BT_URL}" || FW_MISSING=1
fi

if [[ $FW_MISSING -eq 0 ]]; then
    echo "[✓] Firmware Binaries: Verified and ready in ${FIRMWARE_DIR}"
else
    echo "[✗] Firmware Binaries: Failed to download or verify required files"
fi

# [7/7] Power & Regulatory Tweaks
echo "options mt7925e disable_aspm=1" > /etc/modprobe.d/mt7925e.conf
mkdir -p /etc/NetworkManager/conf.d/
echo -e "[connection]\nwifi.powersave = 2" > /etc/NetworkManager/conf.d/disable-powersave.conf
iw reg set "${REG_DOMAIN}" || true
echo "REGDOMAIN=${REG_DOMAIN}" > /etc/default/crda 2>/dev/null || true
echo "[✓] Optimizations: ASPM, Power Saving disabled & RegDomain set to ${REG_DOMAIN}"

# Reload Drivers & Bluetooth with stabilization delays
echo
echo "Waiting for the network interface to stabilize..."
systemctl stop bluetooth || true
modprobe -r btusb btmtk mt7925e 2>/dev/null || true
sleep 1
modprobe mt7925e
modprobe btmtk
modprobe btusb
systemctl start bluetooth || true
sleep 2

WIFI_IFACE=$(ip -br link show type wifi 2>/dev/null | awk '{print $1}' | head -n 1 || true)
if [[ -n "${WIFI_IFACE}" ]]; then
    iw dev "${WIFI_IFACE}" set power_save off 2>/dev/null || true
fi

# ==========================================================
# POST-SETUP SYSTEM DIAGNOSTIC DASHBOARD
# ==========================================================
echo
echo "=========================================================="
echo " System Diagnostic Verification Dashboard"
echo "=========================================================="

# 1. PCIe Hardware Check
if lspci -nn | grep -q -iE 'mediatek|7927|7925'; then
    PCI_NAME=$(lspci -nn | grep -iE 'mediatek|7927|7925' | head -n 1 | cut -d: -f3- | xargs)
    echo "[✓] PCIe Hardware: Detected (${PCI_NAME})"
else
    echo "[✗] PCIe Hardware: MediaTek wireless adapter not found on PCIe bus"
fi

# 2. Kernel Module Status Check
if lsmod | grep -q "^mt7925e"; then
    echo "[✓] Driver Module: mt7925e loaded"
else
    echo "[✗] Driver Module: mt7925e not loaded"
fi

# 3. Wireless Interface Status Check
DETECTED_IFACE=""
if [[ -d /sys/bus/pci/drivers/mt7925e ]]; then
    for dev in /sys/bus/pci/drivers/mt7925e/*/net/*; do
        if [[ -d "$dev" ]]; then
            DETECTED_IFACE=$(basename "$dev")
            break
        fi
    done
fi
if [[ -z "${DETECTED_IFACE}" ]]; then
    DETECTED_IFACE=$(ip -br link show type wifi 2>/dev/null | awk '{print $1}' | head -n 1 || true)
fi

if [[ -n "${DETECTED_IFACE}" ]]; then
    CONN_INFO=$(iw dev "${DETECTED_IFACE}" link 2>/dev/null || true)
    if echo "${CONN_INFO}" | grep -q "Connected to"; then
        SSID=$(echo "${CONN_INFO}" | grep "SSID:" | awk '{print $2}')
        echo "[✓] Wireless Interface: ${DETECTED_IFACE} (Connected to '${SSID}')"
    else
        echo "[✓] Wireless Interface: ${DETECTED_IFACE} (Ready / Disconnected)"
    fi
else
    echo "[✗] Wireless Interface: No active network adapter found (reboot required)"
fi

# 4. Bluetooth Controller Status Check
BT_ACTIVE=0
if command -v bluetoothctl &>/dev/null && bluetoothctl show 2>/dev/null | grep -q "Controller"; then
    BT_ACTIVE=1
elif hciconfig 2>/dev/null | grep -q "hci"; then
    BT_ACTIVE=1
fi

if [[ $BT_ACTIVE -eq 1 ]]; then
    echo "[✓] Bluetooth Controller: Active and responding"
else
    echo "[✗] Bluetooth Controller: Not detected or not responding"
fi

echo "=========================================================="
echo
read -rp "Setup and diagnostics complete. Press Enter to exit..."
