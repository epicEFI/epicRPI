#!/bin/bash
# RPi5 Fast Boot Master Build Script
# This script automates the entire process from a fresh WSL environment.
# Usage: ./build_rpi5_fastboot.sh [--console-only] [--skip-kernel] [--skip-rootfs] [--quick]

set -e

# Configuration
BUILD_DIR="$HOME/rpi5-fastboot"
SOURCES_DIR="$BUILD_DIR/sources"
WINDOWS_WORKSPACE="/mnt/c/rpi-fastboot"
IMG_NAME="rpi5-fastboot.img"
CONSOLE_ONLY=false
SKIP_KERNEL=false
SKIP_ROOTFS=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --console-only)
            CONSOLE_ONLY=true
            echo "[OPT] Console-only mode enabled (no auto X start)"
            ;;
        --skip-kernel)
            SKIP_KERNEL=true
            echo "[OPT] Skipping kernel build"
            ;;
        --skip-rootfs)
            SKIP_ROOTFS=true
            echo "[OPT] Skipping RootFS build (will reconfigure existing)"
            ;;
        --quick)
            SKIP_KERNEL=true
            SKIP_ROOTFS=true
            echo "[OPT] Quick mode: skipping kernel and rootfs builds"
            ;;
    esac
done

echo "=== 1. Installing System Dependencies ==="
sudo apt-get update
sudo apt-get install -y \
    bc build-essential flex bison libssl-dev libncurses5-dev libncursesw5-dev \
    gawk git make python3 python3-dev python3-setuptools swig libpython3-dev \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libgnutls28-dev \
    debootstrap qemu-user-static binfmt-support u-boot-tools parted dosfstools \
    tar xz-utils zstd

# Ensure binfmt is enabled for QEMU
sudo update-binfmts --enable

echo "=== 2. Setting Up Build Directory ==="
mkdir -p "$SOURCES_DIR"
mkdir -p "$WINDOWS_WORKSPACE"
cd "$SOURCES_DIR"

echo "=== 3. Cloning Repositories (Shallow) ==="
[ ! -d "linux" ] && git clone --depth 1 https://github.com/raspberrypi/linux.git
[ ! -d "firmware" ] && git clone --depth 1 https://github.com/raspberrypi/firmware.git

echo "=== 4. Building Linux Kernel ==="
if [[ "$SKIP_KERNEL" == "false" ]]; then
    cd "$SOURCES_DIR/linux"
    if [ ! -f "arch/arm64/boot/Image" ]; then
        # Start fresh with defconfig - bcm2712_defconfig should have all Pi5 drivers
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2712_defconfig
        
        # Pi5 display architecture:
        # - card0 = v3d (3D rendering)
        # - card1 = vc4/axi:gpu (main display controller with HDMI)
        # - card2 = RP1 DPI (optional)
        # We need vc4 built-in (=y) not as module (=m) for reliable HDMI
        ./scripts/config --enable CONFIG_DRM
        ./scripts/config --set-val CONFIG_DRM_V3D y
        ./scripts/config --set-val CONFIG_DRM_VC4 y
        ./scripts/config --enable CONFIG_DRM_VC4_HDMI_CEC
        ./scripts/config --enable CONFIG_DRM_GEM_DMA_HELPER
        ./scripts/config --enable CONFIG_DRM_KMS_HELPER
        ./scripts/config --enable CONFIG_DRM_DISPLAY_HELPER
        ./scripts/config --enable CONFIG_DRM_FBDEV_EMULATION
        ./scripts/config --enable CONFIG_FB
        ./scripts/config --enable CONFIG_FRAMEBUFFER_CONSOLE
        # Disable debug features for faster boot and smaller kernel
        ./scripts/config --disable CONFIG_DEBUG_INFO
        ./scripts/config --disable CONFIG_DEBUG_KERNEL
        ./scripts/config --disable CONFIG_PRINTK_TIME
        ./scripts/config --disable CONFIG_KALLSYMS
        ./scripts/config --disable CONFIG_FTRACE
        ./scripts/config --disable CONFIG_FUNCTION_TRACER
        ./scripts/config --disable CONFIG_STACK_TRACER
        ./scripts/config --disable CONFIG_DYNAMIC_FTRACE
        ./scripts/config --disable CONFIG_PROFILING
        ./scripts/config --disable CONFIG_OPROFILE
        # Console and input subsystem - needed for keyboard input
        ./scripts/config --enable CONFIG_VT_CONSOLE
        ./scripts/config --enable CONFIG_VT
        ./scripts/config --enable CONFIG_INPUT_EVDEV
        # USB and input
        ./scripts/config --enable CONFIG_USB_XHCI_HCD
        ./scripts/config --enable CONFIG_USB_STORAGE
        ./scripts/config --enable CONFIG_USB_UAS
        ./scripts/config --enable CONFIG_USB_HID
        ./scripts/config --enable CONFIG_HID_GENERIC
        ./scripts/config --enable CONFIG_INPUT_KEYBOARD
        ./scripts/config --enable CONFIG_INPUT_MOUSE
        # I2C support for sensors
        ./scripts/config --enable CONFIG_I2C
        ./scripts/config --enable CONFIG_I2C_CHARDEV
        ./scripts/config --enable CONFIG_I2C_BCM2835
        ./scripts/config --enable CONFIG_I2C_BCM2708
        # Enable bh1750 light sensor driver (as module)
        ./scripts/config --enable CONFIG_BH1750
        ./scripts/config --enable CONFIG_IIO
        ./scripts/config --enable CONFIG_IIO_BUFFER
        ./scripts/config --enable CONFIG_IIO_KFIFO_BUF
        # CAN bus support for mcp2515
        ./scripts/config --enable CONFIG_CAN
        ./scripts/config --enable CONFIG_CAN_DEV
        ./scripts/config --enable CONFIG_CAN_MCP251X
        ./scripts/config --enable CONFIG_SPI
        ./scripts/config --enable CONFIG_SPI_BCM2835
        
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image modules dtbs
    else
        echo "Kernel already built, skipping (delete arch/arm64/boot/Image to rebuild)"
    fi
else
    echo "Skipping kernel build as requested"
fi

echo "=== 6. Building RootFS ==="
if [[ "$SKIP_ROOTFS" == "false" ]]; then
    if [ ! -d "$BUILD_DIR/rootfs/bin" ]; then
        sudo rm -rf "$BUILD_DIR/rootfs"
        mkdir -p "$BUILD_DIR/rootfs"
        sudo debootstrap --arch=arm64 --variant=minbase \
            --include=labwc,seatd,libseat1,busybox,kmod,udev,fish,systemd,dbus,libgl1-mesa-dri,mesa-vulkan-drivers,libwayland-client0,libwayland-server0,libegl1,libgles2,libicu76,iproute2,iputils-ping,nano,openssh-server,wget,gnupg,systemd-resolved,can-utils \
            trixie "$BUILD_DIR/rootfs" http://deb.debian.org/debian
    else
        echo "RootFS already exists, skipping debootstrap (delete rootfs dir to rebuild)"
    fi

    # Install kernel modules to rootfs
    cd "$SOURCES_DIR/linux"
    sudo make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$BUILD_DIR/rootfs" modules_install
else
    echo "Skipping RootFS debootstrap as requested"
fi

echo "=== 7. Configuring Auto-Login, Shell, and GUI ==="
ROOTFS="$BUILD_DIR/rootfs"

# Add Raspberry Pi Foundation repository for rpi-eeprom and other Pi packages
# Use bookworm (stable) as Raspberry Pi repos may not have all Debian versions
sudo mkdir -p "$ROOTFS/etc/apt/sources.list.d"
sudo mkdir -p "$ROOTFS/usr/share/keyrings"
# Download GPG key
sudo wget -q -O - https://archive.raspberrypi.org/debian/raspberrypi.gpg.key | sudo gpg --dearmor -o "$ROOTFS/usr/share/keyrings/raspberrypi-archive-keyring.gpg"

# Configure main Debian sources with all components (main, contrib, non-free, non-free-firmware)
# Note: "universe multiverse restricted" are Ubuntu terms; Debian uses "main contrib non-free"
sudo tee "$ROOTFS/etc/apt/sources.list" > /dev/null << 'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
EOF

# Configure Raspberry Pi Foundation repository (use trixie to match Debian version)
sudo tee "$ROOTFS/etc/apt/sources.list.d/raspberrypi.list" > /dev/null << 'EOF'
deb [signed-by=/usr/share/keyrings/raspberrypi-archive-keyring.gpg] http://archive.raspberrypi.org/debian/ trixie main
EOF

# Install Raspberry Pi Foundation packages (rpi-eeprom, raspi-config) now that repo is configured
# Note: RPi archive key still uses SHA1 in signatures; Debian rejects SHA1 as of 2026-02-01.
# Allow insecure repo for this step until RPi Foundation publishes an updated key.
echo "=== 7a. Installing Raspberry Pi Foundation Packages ==="
sudo chroot "$ROOTFS" /bin/bash -c "apt-get update -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true" 2>&1
sudo chroot "$ROOTFS" /bin/bash -c "apt-get install -y -o Acquire::AllowInsecureRepositories=true rpi-eeprom raspi-config" 2>&1 || echo "Warning: Could not install rpi-eeprom/raspi-config (may need manual install after boot)"

# Configure EEPROM boot order to prioritize USB (0xf14 = USB, then SD, then network)
# This improves boot times by scanning USB first
# Create a first-boot script to apply EEPROM config (EEPROM can only be updated on actual hardware)
echo "=== 7b. Configuring EEPROM Boot Order ==="
sudo mkdir -p "$ROOTFS/usr/local/bin"
sudo tee "$ROOTFS/usr/local/bin/apply-eeprom-config" > /dev/null << 'EOF'
#!/bin/bash
# Apply EEPROM boot order configuration on first boot
if [ ! -f /var/lib/rpi-eeprom-config-applied ]; then
    if command -v rpi-eeprom-config >/dev/null 2>&1; then
        # Create EEPROM config with USB boot priority
        cat > /tmp/pieeprom.conf << 'INNER_EOF'
[all]
BOOT_ORDER=0xf14
INNER_EOF
        # Apply the config (requires root, runs as systemd service)
        rpi-eeprom-config --apply /tmp/pieeprom.conf 2>/dev/null && touch /var/lib/rpi-eeprom-config-applied
        rm -f /tmp/pieeprom.conf
        # Note: EEPROM update will be applied on next reboot
    fi
fi
EOF
sudo chmod +x "$ROOTFS/usr/local/bin/apply-eeprom-config"

# Create systemd service to run on first boot
sudo mkdir -p "$ROOTFS/etc/systemd/system"
sudo tee "$ROOTFS/etc/systemd/system/apply-eeprom-config.service" > /dev/null << 'EOF'
[Unit]
Description=Apply EEPROM Boot Order Configuration
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/apply-eeprom-config
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo chroot "$ROOTFS" /bin/bash -c "systemctl enable apply-eeprom-config.service" 2>/dev/null || true

# Set proper hostname (not inherited from WSL)
echo "rpi5" | sudo tee "$ROOTFS/etc/hostname" > /dev/null
sudo tee "$ROOTFS/etc/hosts" > /dev/null << 'EOF'
127.0.0.1       localhost
127.0.1.1       rpi5
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

# Ensure vc4 module loads at boot (fallback if built as module)
sudo mkdir -p "$ROOTFS/etc/modules-load.d"
sudo tee "$ROOTFS/etc/modules-load.d/gpu.conf" > /dev/null << 'EOF'
vc4
v3d
EOF

# Ensure i2c-dev module loads for I2C device access
sudo tee "$ROOTFS/etc/modules-load.d/i2c.conf" > /dev/null << 'EOF'
i2c-dev
EOF

# Auto-load bh1750 light sensor driver module
sudo tee "$ROOTFS/etc/modules-load.d/bh1750.conf" > /dev/null << 'EOF'
bh1750
EOF

# Blacklist Bluetooth and WiFi modules to prevent loading
sudo mkdir -p "$ROOTFS/etc/modprobe.d"
sudo tee "$ROOTFS/etc/modprobe.d/disable-wifi-bt.conf" > /dev/null << 'EOF'
blacklist brcmfmac
blacklist brcmutil
blacklist bluetooth
blacklist btbcm
blacklist hci_uart
EOF

# Configure systemd-networkd for ethernet DHCP
# Pi5 uses "end0" interface name (predictable interface naming)
sudo mkdir -p "$ROOTFS/etc/systemd/network"
sudo tee "$ROOTFS/etc/systemd/network/20-ethernet.network" > /dev/null << 'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
DNS=8.8.8.8 8.8.4.4 1.1.1.1
EOF

# Configure systemd-resolved for DNS resolution
sudo mkdir -p "$ROOTFS/etc/systemd"
sudo tee "$ROOTFS/etc/systemd/resolved.conf" > /dev/null << 'EOF'
[Resolve]
DNS=8.8.8.8 8.8.4.4 1.1.1.1
FallbackDNS=8.8.8.8 8.8.4.4
EOF
sudo chroot "$ROOTFS" /bin/bash -c "systemctl enable systemd-resolved" 2>/dev/null || true

# Create symlink for systemd-resolved to work properly
# Remove any existing resolv.conf and create symlink to systemd-resolved stub
sudo rm -f "$ROOTFS/etc/resolv.conf"
sudo mkdir -p "$ROOTFS/run/systemd/resolve"
sudo ln -s /run/systemd/resolve/stub-resolv.conf "$ROOTFS/etc/resolv.conf"

# Create fallback static resolv.conf in case systemd-resolved isn't available
# This ensures DNS works even if systemd-resolved fails to start
sudo tee "$ROOTFS/etc/resolv.conf.fallback" > /dev/null << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

# Enable seatd for Wayland seat management
sudo chroot "$ROOTFS" /bin/bash -c "systemctl enable seatd" 2>/dev/null || true
# Enable systemd-networkd for ethernet networking
sudo chroot "$ROOTFS" /bin/bash -c "systemctl enable systemd-networkd" 2>/dev/null || true
# Disable SSH from auto-starting (installed but not enabled)
sudo chroot "$ROOTFS" /bin/bash -c "systemctl disable ssh" 2>/dev/null || true
sudo chroot "$ROOTFS" /bin/bash -c "systemctl disable ssh.service" 2>/dev/null || true
# Add root to seat group for direct access
sudo chroot "$ROOTFS" /bin/bash -c "usermod -a -G video,render,input root" 2>/dev/null || true

# Set fish as default shell for root
sudo chroot "$ROOTFS" /bin/bash -c "chsh -s /usr/bin/fish root"

# Set root password to 'raspberry'
echo 'root:raspberry' | sudo chroot "$ROOTFS" chpasswd

# Enable root password login in SSH
sudo mkdir -p "$ROOTFS/etc/ssh"
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' "$ROOTFS/etc/ssh/sshd_config" 2>/dev/null || true
sudo sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' "$ROOTFS/etc/ssh/sshd_config" 2>/dev/null || true
sudo sed -i 's/#PermitRootLogin no/PermitRootLogin yes/' "$ROOTFS/etc/ssh/sshd_config" 2>/dev/null || true
sudo sed -i 's/PermitRootLogin no/PermitRootLogin yes/' "$ROOTFS/etc/ssh/sshd_config" 2>/dev/null || true
# If the line doesn't exist, add it
if ! grep -q "PermitRootLogin" "$ROOTFS/etc/ssh/sshd_config"; then
    echo "PermitRootLogin yes" | sudo tee -a "$ROOTFS/etc/ssh/sshd_config" > /dev/null
fi

# Auto-login on tty1
sudo mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d/"
sudo tee "$ROOTFS/etc/systemd/system/getty@tty1.service.d/override.conf" > /dev/null << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
Type=idle
EOF

# Fish config for auto-start labwc/Wayland (only if not console-only mode)
sudo mkdir -p "$ROOTFS/root/.config/fish"
sudo mkdir -p "$ROOTFS/root/.config/labwc"

if [[ "$CONSOLE_ONLY" == "false" ]]; then
    sudo tee "$ROOTFS/root/.config/fish/config.fish" > /dev/null << 'EOF'
# Clear any inherited environment variables from build
set -e DISPLAY
set -e WAYLAND_DISPLAY

if test (tty) = "/dev/tty1"
    # Start labwc (Wayland compositor)
    set -x XDG_RUNTIME_DIR /run/user/0
    exec labwc
end
EOF
else
    sudo tee "$ROOTFS/root/.config/fish/config.fish" > /dev/null << 'EOF'
# Console-only mode: Wayland auto-start disabled for debugging
# Clear any inherited environment variables from build
set -e DISPLAY
set -e WAYLAND_DISPLAY

# To start Wayland manually, run: sw
function sw
    set -x XDG_RUNTIME_DIR /run/user/0
    labwc
end
EOF
fi

# Create a clean .profile that unsets inherited variables
sudo tee "$ROOTFS/root/.profile" > /dev/null << 'EOF'
# Clean environment on login
unset DISPLAY
unset WAYLAND_DISPLAY
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF

# Wayland/Cage environment setup
# Clear any inherited environment variables in /etc/environment
sudo tee "$ROOTFS/etc/environment" > /dev/null << 'EOF'
# Clean environment for RPi5 fast boot with Wayland
# Wayland compositor sets WAYLAND_DISPLAY automatically
XDG_RUNTIME_DIR=/run/user/0
EOF

# Create XDG_RUNTIME_DIR for Wayland
sudo mkdir -p "$ROOTFS/run/user/0"
sudo chmod 700 "$ROOTFS/run/user/0"

# Create a wrapper script for labwc that sets up environment
sudo tee "$ROOTFS/usr/local/bin/start-wayland" > /dev/null << 'EOF'
#!/bin/sh
# Ensure clean environment before starting Wayland
unset DISPLAY
unset WAYLAND_DISPLAY
export HOME=/root
export XDG_RUNTIME_DIR=/run/user/0

# Create runtime dir if needed
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Check if DRI devices exist
if [ ! -e /dev/dri/card0 ]; then
    echo "ERROR: No DRI devices found. GPU driver may not be loaded."
    echo "Try: ls -la /dev/dri/"
    echo "Try: dmesg | grep -i drm"
    exit 1
fi

# Start labwc
exec labwc "$@"
EOF
sudo chmod +x "$ROOTFS/usr/local/bin/start-wayland"

echo "=== 8. Assembling Final Image ==="
BOOT_DIR="$BUILD_DIR/boot_partition"
mkdir -p "$BOOT_DIR"
cp "$SOURCES_DIR/firmware/boot/fixup"* "$BOOT_DIR/"
cp "$SOURCES_DIR/firmware/boot/start"* "$BOOT_DIR/"
cp "$SOURCES_DIR/linux/arch/arm64/boot/dts/broadcom/bcm2712-rpi-5-b.dtb" "$BOOT_DIR/"
mkdir -p "$BOOT_DIR/overlays"
cp "$SOURCES_DIR/linux/arch/arm64/boot/dts/overlays/"*.dtbo "$BOOT_DIR/overlays/"
cp "$SOURCES_DIR/linux/arch/arm64/boot/Image" "$BOOT_DIR/kernel8.img"

# Create config.txt - boot directly with RPi bootloader (faster than U-Boot, works with USB)
# U-Boot has incomplete USB support on RPi5, so we use native bootloader
cat << 'EOF' > "$BOOT_DIR/config.txt"
arm_64bit=1
device_tree=bcm2712-rpi-5-b.dtb
kernel=kernel8.img
disable_splash=1
boot_delay=0

# Pi5 uses vc4-kms-v3d-pi5, not vc4-kms-v3d
dtoverlay=vc4-kms-v3d-pi5

# Disable Bluetooth and WiFi
dtoverlay=disable-bt
dtoverlay=disable-wifi

# Enable I2C interface (matches raspi-config behavior)
dtoverlay=i2c1

# Enable SPI and MCP2515 CAN bus controller
dtoverlay=spi
dtoverlay=mcp2515-can0,oscillator=12000000,interrupt=25

# Force HDMI hotplug (skip detection wait, but allow EDID for auto-resolution)
hdmi_force_hotplug=1

# Disable HDMI CEC (Consumer Electronics Control)
hdmi_ignore_cec=1
hdmi_ignore_cec_init=1

# Disable camera (MIPI CSI) interface
start_x=0
camera_auto_detect=0

# GPU memory for graphics (increase for better compatibility)
gpu_mem=256

# Enable USB max current (1.2A instead of default)
usb_max_current_enable=1

# Disable under-voltage warnings (power supply warning during shutdown)
# Note: Pi5 doesn't fully power off - enters low-power state by design
avoid_warnings=1
EOF

# Create cmdline.txt for kernel parameters
# Use PARTUUID for root device to work with both SD and USB
# Use both tty1 (HDMI) and ttyS0 (serial) for console access
# Optimized for fast boot: quiet, loglevel=3, logo.nologo, no cursor, consoleblank disabled
cat << 'EOF' > "$BOOT_DIR/cmdline.txt"
console=tty1 console=ttyS0,115200 root=PARTUUID=@ROOTPARTUUID@ rootfstype=ext4 rootwait rw quiet loglevel=3 logo.nologo vt.global_cursor_default=0 consoleblank=0 fsck.repair=yes init=/lib/systemd/systemd
EOF

# Also create U-Boot boot.scr for SD card (optional fallback)
cat << 'EOF' > "$BUILD_DIR/boot.cmd"
fatload mmc 0:1 ${kernel_addr_r} kernel8.img
fatload mmc 0:1 ${fdt_addr_r} bcm2712-rpi-5-b.dtb
setenv bootargs "console=tty1 console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/lib/systemd/systemd"
booti ${kernel_addr_r} - ${fdt_addr_r}
EOF
mkimage -A arm64 -T script -C none -n "Boot Script" -d "$BUILD_DIR/boot.cmd" "$BOOT_DIR/boot.scr"

echo "=== 9. Creating Disk Image (2GB) ==="
IMG_FILE="$BUILD_DIR/$IMG_NAME"
dd if=/dev/zero of="$IMG_FILE" bs=1M count=2048
sudo parted "$IMG_FILE" --script mklabel msdos
sudo parted "$IMG_FILE" --script mkpart primary fat32 1MiB 257MiB
sudo parted "$IMG_FILE" --script mkpart primary ext4 257MiB 100%

LOOP_DEV=$(sudo losetup -f --show --partscan "$IMG_FILE")
sudo mkfs.vfat -F 32 "${LOOP_DEV}p1"
sudo mkfs.ext4 "${LOOP_DEV}p2"

# Get the PARTUUID of both boot and root partitions
BOOT_PARTUUID=$(sudo blkid -s PARTUUID -o value "${LOOP_DEV}p1")
ROOT_PARTUUID=$(sudo blkid -s PARTUUID -o value "${LOOP_DEV}p2")
echo "Boot partition PARTUUID: $BOOT_PARTUUID"
echo "Root partition PARTUUID: $ROOT_PARTUUID"

# Update cmdline.txt with the actual PARTUUID
sed -i "s/@ROOTPARTUUID@/$ROOT_PARTUUID/" "$BOOT_DIR/cmdline.txt"

MOUNT_BOOT="/mnt/rpi_boot"
MOUNT_ROOT="/mnt/rpi_root"
sudo mkdir -p "$MOUNT_BOOT" "$MOUNT_ROOT"
sudo mount "${LOOP_DEV}p1" "$MOUNT_BOOT"
sudo mount "${LOOP_DEV}p2" "$MOUNT_ROOT"

sudo cp -r "$BOOT_DIR/"* "$MOUNT_BOOT/"
sudo cp -a "$BUILD_DIR/rootfs/"* "$MOUNT_ROOT/"

# Update fstab in rootfs to mount both boot and root partitions using PARTUUID
sudo tee "$MOUNT_ROOT/etc/fstab" > /dev/null << EOF
PARTUUID=$BOOT_PARTUUID  /boot  vfat  defaults,noatime  0  2
PARTUUID=$ROOT_PARTUUID  /  ext4  defaults,noatime  0  1
EOF

sudo umount "$MOUNT_BOOT"
sudo umount "$MOUNT_ROOT"
sudo losetup -d "$LOOP_DEV"

echo "=== 10. Copying Image to Windows Workspace ==="
cp "$IMG_FILE" "$WINDOWS_WORKSPACE/"

echo "SUCCESS! Build complete. Image copied to $WINDOWS_WORKSPACE/$IMG_NAME"
