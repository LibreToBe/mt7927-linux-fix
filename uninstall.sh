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
echo " MediaTek MT7927 Wi-Fi 7 & Bluetooth Uninstaller          "
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

# 6. Clean up newer/orphaned kernels and update boot entries
CURRENT_KERNEL="$(uname -r)"

# Find all installed kernel-related packages excluding the currently running one
INSTALLED_PACKAGES=$(dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*' 'linux-headers-[0-9]*' 'linux-modules-[0-9]*' 2>/dev/null || true)
NEWER_PACKAGES=()

while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    # Skip packages belonging to the currently running kernel version
    if [[ "$pkg" == *"$CURRENT_KERNEL"* ]]; then
        continue
    fi
    
    # Extract version string from package name
    PKG_VER=$(echo "$pkg" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' || true)
    [[ -z "$PKG_VER" ]] && continue

    # Compare versions to find newer kernels
    HIGHEST=$(printf "%s\n%s\n" "$CURRENT_KERNEL" "$PKG_VER" | sort -V | tail -n1)
    if [[ "$HIGHEST" == "$PKG_VER" && "$PKG_VER" != "$CURRENT_KERNEL" ]]; then
        NEWER_PACKAGES+=("$pkg")
    fi
done <<< "$INSTALLED_PACKAGES"

# Deduplicate array elements
mapfile -t NEWER_PACKAGES < <(printf "%s\n" "${NEWER_PACKAGES[@]}" | sort -u)

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
            
            echo "[!] Cleaning up leftover dependencies..."
            apt-get autoremove -y
            
            echo "[!] Updating GRUB and EFI boot entries..."
            update-grub
            
            # If systemd-boot is used instead of GRUB
            if command -v bootctl &>/dev/null && [[ -d /efi/loader || -d /boot/loader ]]; then
                bootctl update || true
            fi
            
            echo "[✓] Newer kernels purged and bootloader updated successfully"
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
