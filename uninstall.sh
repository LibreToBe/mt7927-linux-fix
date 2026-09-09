#!/usr/bin/env bash
set -euo pipefail

MODULE="mediatek-mt7927"
VERSION="2.9"
TARGET_SRC="/usr/src/${MODULE}-${VERSION}"
FIRMWARE_DIR="/lib/firmware/mediatek/mt7927"

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
echo " MediaTek MT7927 Wi-Fi 7 & Bluetooth Uninstaller         "
echo "=========================================================="
echo

# 1. Remove DKMS Module silently if present
if dkms status 2>/dev/null | grep -q "${MODULE}/${VERSION}"; then
    echo "[!] Removing DKMS module (${MODULE}/${VERSION})..."
    dkms remove -m "$MODULE" -v "$VERSION" --all &>/dev/null || true
    echo "[✓] DKMS module removed"
else
    echo "[✓] DKMS module not found (already removed or never installed)"
fi

# 2. Clean up Source Files
if [[ -d "$TARGET_SRC" ]]; then
    rm -rf "$TARGET_SRC"
    echo "[✓] Source directory removed"
fi

# 3. Remove Firmware Files
if [[ -d "$FIRMWARE_DIR" ]]; then
    rm -rf "$FIRMWARE_DIR"
    echo "[✓] Firmware directory removed"
fi

# 4. Remove Configurations (ASPM, Power Saving, RegDomain)
rm -f /etc/modprobe.d/mt7925e.conf
rm -f /etc/NetworkManager/conf.d/disable-powersave.conf
rm -f /etc/default/crda
echo "[✓] Configuration overrides removed"

# 5. Unload Driver Modules & Refresh silently
modprobe -r mt7925e btmtk btusb &>/dev/null || true
depmod -a &>/dev/null || true
echo "[✓] Kernel module dependencies refreshed"

# 6. Optional: Clean up newer/orphaned kernels causing "bad shim lock" errors
CURRENT_KERNEL="$(uname -r)"
CURRENT_VER_STR=$(echo "$CURRENT_KERNEL" | cut -d- -f1,2)

INSTALLED_PACKAGES=$(dpkg-query -W -f='${Package}\n' 'linux-image-*' 'linux-headers-*' 'linux-modules-*' 2>/dev/null | grep -E '[0-9]+\.[0-9]+\.[0-9]+' || true)
NEWER_PACKAGES=()

while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if [[ "$pkg" == *"${CURRENT_VER_STR}"* ]] || [[ "$pkg" == *-generic ]]; then
        continue
    fi
    PKG_VER=$(echo "$pkg" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' || true)
    [[ -z "$PKG_VER" ]] && continue

    HIGHEST=$(printf "%s\n%s\n" "$CURRENT_VER_STR" "$PKG_VER" | sort -V | tail -n1)
    if [[ "$HIGHEST" == "$PKG_VER" && "$PKG_VER" != "$CURRENT_VER_STR" ]]; then
        NEWER_PACKAGES+=("$pkg")
    fi
done <<< "$INSTALLED_PACKAGES"

if [[ ${#NEWER_PACKAGES[@]} -gt 0 ]]; then
    echo
    echo "=========================================================="
    echo " Found newer/orphaned kernel packages (shim lock risk):   "
    echo "=========================================================="
    for p in "${NEWER_PACKAGES[@]}"; do
        echo " - $p"
    done
    echo "=========================================================="
    read -rp "Do you want to purge these newer kernels now? (y/N): " kernel_choice
    case "$kernel_choice" in
        y|Y )
            echo "[!] Purging newer kernel packages..."
            apt-get purge -y "${NEWER_PACKAGES[@]}"
            echo "[!] Updating GRUB bootloader..."
            update-grub
            echo "[✓] Newer kernels purged successfully"
            ;;
        * )
            echo "[i] Skipping newer kernel removal."
            ;;
    esac
fi

echo
echo "=========================================================="
echo "[✓] Uninstallation complete! A system reboot is recommended."
echo "=========================================================="
echo
read -rp "Press Enter to exit..."
