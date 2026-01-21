#!/bin/bash
# Step-by-step script to defer non-critical services until after RealDash starts
# Run this on your Raspberry Pi 5

set -e

echo "=== Step 1: Check current service status ==="
echo "Checking which services are enabled and their current dependencies..."
systemctl is-enabled realdash.service || echo "WARNING: realdash.service not found/enabled"
systemctl is-enabled systemd-networkd.service || echo "systemd-networkd not enabled"
systemctl is-enabled systemd-resolved.service || echo "systemd-resolved not enabled"
systemctl is-enabled ssh.service || echo "ssh not enabled"
systemctl is-enabled rpi-eeprom-update.service || echo "rpi-eeprom-update not enabled"
echo ""

echo "=== Step 2: Disable and mask rpi-eeprom-update (not needed every boot) ==="
sudo systemctl stop rpi-eeprom-update.service 2>/dev/null || true
sudo systemctl disable rpi-eeprom-update.service 2>/dev/null || true
sudo systemctl disable rpi-eeprom-update.timer 2>/dev/null || true
sudo systemctl mask rpi-eeprom-update.service 2>/dev/null || true
echo "✓ rpi-eeprom-update disabled and masked"
echo ""

echo "=== Step 3: Disable SSH (if not needed) ==="
read -p "Disable SSH service? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo systemctl stop ssh.service 2>/dev/null || true
    sudo systemctl disable ssh.service 2>/dev/null || true
    echo "✓ SSH disabled"
else
    echo "Keeping SSH enabled (will defer until after RealDash)"
fi
echo ""

echo "=== Step 4: Create post-realdash service to start deferred services ==="
sudo tee /etc/systemd/system/post-realdash.service > /dev/null << 'EOF'
[Unit]
Description=Start non-critical services after RealDash
After=realdash.service
Wants=realdash.service
DefaultDependencies=no

[Service]
Type=oneshot
# Start these services after RealDash is running
ExecStart=/bin/sh -c 'systemctl start systemd-networkd systemd-resolved ssh 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable post-realdash.service
echo "✓ post-realdash.service created and enabled"
echo ""

echo "=== Step 5: Modify services to start AFTER RealDash (instead of in parallel) ==="

# Modify systemd-networkd to start after RealDash
if systemctl is-enabled systemd-networkd.service >/dev/null 2>&1; then
    sudo mkdir -p /etc/systemd/system/systemd-networkd.service.d
    sudo tee /etc/systemd/system/systemd-networkd.service.d/after-realdash.conf > /dev/null << 'EOF'
[Unit]
After=realdash.service
EOF
    echo "✓ systemd-networkd will start after RealDash"
fi

# Modify systemd-resolved to start after RealDash
if systemctl is-enabled systemd-resolved.service >/dev/null 2>&1; then
    sudo mkdir -p /etc/systemd/system/systemd-resolved.service.d
    sudo tee /etc/systemd/system/systemd-resolved.service.d/after-realdash.conf > /dev/null << 'EOF'
[Unit]
After=realdash.service
EOF
    echo "✓ systemd-resolved will start after RealDash"
fi

# Modify SSH to start after RealDash (if still enabled)
if systemctl is-enabled ssh.service >/dev/null 2>&1; then
    sudo mkdir -p /etc/systemd/system/ssh.service.d
    sudo tee /etc/systemd/system/ssh.service.d/after-realdash.conf > /dev/null << 'EOF'
[Unit]
After=realdash.service
EOF
    echo "✓ SSH will start after RealDash"
fi

# Modify apply-eeprom-config to not wait for network (already done in build script, but ensure it)
if [ -f /etc/systemd/system/apply-eeprom-config.service ]; then
    sudo mkdir -p /etc/systemd/system/apply-eeprom-config.service.d
    sudo tee /etc/systemd/system/apply-eeprom-config.service.d/no-network-wait.conf > /dev/null << 'EOF'
[Unit]
ConditionPathExists=!/var/lib/rpi-eeprom-config-applied
After=local-fs.target
EOF
    echo "✓ apply-eeprom-config optimized"
fi

sudo systemctl daemon-reload
echo ""

echo "=== Step 6: Configure journald to use volatile storage (faster, no flush needed) ==="
read -p "Use RAM-only journald storage? (logs lost on reboot, but faster boot) (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo mkdir -p /etc/systemd/journald.conf.d
    sudo tee /etc/systemd/journald.conf.d/fastboot.conf > /dev/null << 'EOF'
[Journal]
Storage=volatile
EOF
    echo "✓ journald configured for volatile storage (no flush delay)"
else
    echo "Keeping persistent journald storage"
fi
echo ""

echo "=== Step 7: Verify changes ==="
echo "Checking service dependencies..."
echo ""
echo "RealDash dependencies:"
systemctl show realdash.service | grep -E "^After=|^Wants=" || true
echo ""
echo "Network services now depend on RealDash:"
systemctl show systemd-networkd.service | grep -E "^After=" || true
systemctl show systemd-resolved.service | grep -E "^After=" || true
echo ""

echo "=== Step 8: Show what will happen on next boot ==="
echo "Run these commands after reboot to verify:"
echo "  systemd-analyze blame | head -20"
echo "  systemd-analyze critical-chain realdash.service"
echo "  systemctl status post-realdash.service"
echo ""

echo "=== DONE ==="
echo ""
echo "Summary of changes:"
echo "  ✓ rpi-eeprom-update: disabled and masked"
echo "  ✓ systemd-networkd: starts AFTER RealDash"
echo "  ✓ systemd-resolved: starts AFTER RealDash"
echo "  ✓ ssh: starts AFTER RealDash (or disabled if you chose)"
echo "  ✓ post-realdash.service: created to batch-start deferred services"
echo "  ✓ journald: optionally configured for volatile storage"
echo ""
echo "Reboot to test: sudo reboot"
echo "After reboot, check boot time: systemd-analyze blame"
