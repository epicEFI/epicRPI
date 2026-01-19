#!/bin/bash
# Realdash Installation Script
# This script is called by build_rpi5_fastboot.sh to customize the rootfs for realdash
# The ROOTFS variable is passed from the build script

set -e

# Check if ROOTFS is set
if [ -z "$ROOTFS" ]; then
    echo "Error: ROOTFS variable not set"
    exit 1
fi

if [ ! -d "$ROOTFS" ]; then
    echo "Error: ROOTFS directory does not exist: $ROOTFS"
    exit 1
fi

echo "=== Installing RealDash UI customization for rootfs: $ROOTFS ==="

# ============================================================================
# 1. Install Wayland/Weston Dependencies
# ============================================================================
echo "Installing Wayland/Weston packages..."
sudo chroot "$ROOTFS" /bin/bash -c "apt-get update" 2>&1
sudo chroot "$ROOTFS" /bin/bash -c "apt-get install -y weston xwayland wayland-protocols libwayland-dev" 2>&1

# ============================================================================
# 2. Install RealDash Dependencies
# ============================================================================
echo "Installing RealDash dependencies..."
sudo chroot "$ROOTFS" /bin/bash -c "apt-get install -y libopenal1 libvlc5 gpiod espeak-ng wget" 2>&1

# ============================================================================
# 3. Download and Install RealDash Package
# ============================================================================
# Note: RealDash version and URL need to be configured
# Default to a placeholder version - user should update this or make it configurable
REALDASH_VERSION="${REALDASH_VERSION:-2.4.4}"
REALDASH_DEB="realdash-mrd_${REALDASH_VERSION}_arm64.deb"
REALDASH_URL="https://my.realdash.net/downloads/${REALDASH_DEB}"

echo "Downloading RealDash package (version ${REALDASH_VERSION})..."
# Download to a temp location first, then copy to rootfs
TMP_DEB="/tmp/${REALDASH_DEB}"
if [ ! -f "$TMP_DEB" ]; then
    echo "Warning: RealDash package not found at $TMP_DEB"
    echo "Please download RealDash .deb package manually or update REALDASH_VERSION"
    echo "Skipping RealDash package installation (dependencies installed)"
else
    # Copy package to rootfs and install
    sudo cp "$TMP_DEB" "$ROOTFS/tmp/${REALDASH_DEB}"
    sudo chroot "$ROOTFS" /bin/bash -c "dpkg -i /tmp/${REALDASH_DEB} || apt-get install -f -y" 2>&1
    sudo rm -f "$ROOTFS/tmp/${REALDASH_DEB}"
fi

# ============================================================================
# 4. Configure Weston Auto-Start (Replace labwc)
# ============================================================================
echo "Configuring Weston auto-start..."
# Replace labwc with weston in fish config
sudo mkdir -p "$ROOTFS/root/.config/fish"
sudo tee "$ROOTFS/root/.config/fish/config.fish" > /dev/null << 'EOF'
# Clear any inherited environment variables from build
set -e DISPLAY
set -e WAYLAND_DISPLAY

if test (tty) = "/dev/tty1"
    # Start weston (Wayland compositor for RealDash)
    set -x XDG_RUNTIME_DIR /run/user/0
    mkdir -p $XDG_RUNTIME_DIR
    chmod 700 $XDG_RUNTIME_DIR
    exec weston --backend=drm-backend.so --tty=1
end
EOF

# ============================================================================
# 5. Create Weston Configuration
# ============================================================================
echo "Creating Weston configuration..."
sudo mkdir -p "$ROOTFS/root/.config"
sudo tee "$ROOTFS/root/.config/weston.ini" > /dev/null << 'EOF'
[core]
# Use DRM backend for direct hardware access
backend=drm-backend.so

[output]
# Preferred resolution (1920x1080 works better than 4K per user feedback)
# If not specified, EDID will be used (already configured in base image)
# mode=1920x1080@60

[screen]
# Disable screen locking
lock=false

[shell]
# Start in fullscreen mode
locking=false
EOF

# ============================================================================
# 6. Create RealDash Systemd Service
# ============================================================================
echo "Creating RealDash systemd service..."
sudo mkdir -p "$ROOTFS/etc/systemd/system"
sudo tee "$ROOTFS/etc/systemd/system/realdash.service" > /dev/null << 'EOF'
[Unit]
Description=RealDash Dashboard
After=graphical.target weston.service
Wants=weston.service

[Service]
Type=simple
User=root
Environment="XDG_RUNTIME_DIR=/run/user/0"
Environment="WAYLAND_DISPLAY=wayland-0"
# RealDash may need X11 via XWayland
Environment="DISPLAY=:0"
# Wait for weston to be ready
ExecStartPre=/bin/sleep 2
ExecStart=/usr/bin/realdash
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

# Enable RealDash service
sudo chroot "$ROOTFS" /bin/bash -c "systemctl enable realdash.service" 2>/dev/null || true

# ============================================================================
# 7. Create Weston Systemd Service (if not using fish auto-start)
# ============================================================================
# Alternative: Use systemd to start weston instead of fish config
# For now, we'll use fish config, but create service as backup
sudo tee "$ROOTFS/etc/systemd/system/weston.service" > /dev/null << 'EOF'
[Unit]
Description=Weston Wayland Compositor
After=graphical.target

[Service]
Type=simple
User=root
Environment="XDG_RUNTIME_DIR=/run/user/0"
ExecStart=/usr/bin/weston --backend=drm-backend.so --tty=1
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

# ============================================================================
# 8. Set Up Permissions and Environment
# ============================================================================
echo "Setting up permissions..."

# Ensure root has access to CAN bus (already configured in base, but verify)
# CAN bus permissions are typically handled via udev rules or group membership
# Base image already has can-utils installed

# GPIO permissions - add root to gpio group if it exists
sudo chroot "$ROOTFS" /bin/bash -c "getent group gpio >/dev/null 2>&1 && usermod -a -G gpio root || true" 2>&1

# Create XDG_RUNTIME_DIR directory
sudo mkdir -p "$ROOTFS/run/user/0"
sudo chmod 700 "$ROOTFS/run/user/0"

# ============================================================================
# 9. Additional RealDash Configuration
# ============================================================================
echo "Configuring RealDash environment..."

# Create RealDash config directory if needed
sudo mkdir -p "$ROOTFS/root/.config/realdash"

# Add environment variables to /etc/environment for RealDash
sudo tee -a "$ROOTFS/etc/environment" > /dev/null << 'EOF'

# RealDash environment
XDG_RUNTIME_DIR=/run/user/0
WAYLAND_DISPLAY=wayland-0
EOF

# ============================================================================
# 10. Cleanup
# ============================================================================
echo "Cleaning up..."
sudo chroot "$ROOTFS" /bin/bash -c "apt-get clean" 2>&1

echo "=== RealDash installation completed ==="
echo "Note: RealDash .deb package must be downloaded separately if not found"
echo "Set REALDASH_VERSION environment variable to specify version"
echo "Example: REALDASH_VERSION=2.4.4 ./build_rpi5_fastboot.sh --ui realdash"
