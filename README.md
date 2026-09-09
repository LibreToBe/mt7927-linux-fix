# I am fixing some faults and shim problems regarding secure boot.
# For now disable secure-boot for the script to work & keep it disabled for the fix to persist.

# 🚀 MediaTek MT7927 (Filogic 380) Linux Setup & Diagnostics

An all-in-one bash script to automate the installation, configuration, and troubleshooting of the **MediaTek MT7927 Wi-Fi 7 & Bluetooth PCIe adapter** on Linux. 

Out of the box, getting this card to work on older kernels can be frustrating due to missing firmware, missing in-tree drivers, and aggressive power-saving drops. This script handles everything from compiling the DKMS driver to downloading the latest firmware and applying necessary stability patches.

## ✨ Features

- **Smart Kernel Detection**: Automatically uses native in-tree drivers on Kernel 7.1+ or compiles the out-of-tree `mt7925e` DKMS driver on older kernels.
- **Dependency Management**: Installs missing build tools (`dkms`, `linux-headers`, etc.) automatically.
- **Firmware Fetcher**: Pulls the exact required `WIFI_RAM_CODE` and `BT_RAM_CODE` binaries directly from the official Linux firmware repositories.
- **Stability Tweaks**: Disables PCIe ASPM and NetworkManager power-saving features to prevent unexpected disconnects and lag spikes.
- **Diagnostic Dashboard**: Runs a clean `[✓] / [✗]` post-install check on your PCIe bus, kernel modules, network interface, and Bluetooth controller.

## 📋 Prerequisites

- A **Debian/Ubuntu-based** Linux distribution (uses `apt-get` for dependencies).
- An active internet connection (via ethernet or tethering) to download packages and firmware.
- Sudo/Root privileges.

## 🛠️ Usage

**Clone the repository or download the script**
