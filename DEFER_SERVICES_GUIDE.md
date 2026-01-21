# Defer Services After RealDash - Step-by-Step Guide

This guide shows you how to make non-critical services start **after** RealDash, so your Pi boots faster and RealDash appears sooner.

## Quick Start (On Your Current Pi)

### Option A: Automated Script (Recommended)
```bash
# Copy the script to your Pi, then run:
chmod +x defer-services-after-realdash.sh
sudo ./defer-services-after-realdash.sh
```

The script will:
- Ask you which services to disable
- Configure all services to start after RealDash
- Show you verification commands

### Option B: Manual Commands (Step-by-Step)

#### Step 1: Check Current Status
```bash
systemctl is-enabled realdash.service
systemctl is-enabled systemd-networkd.service
systemctl is-enabled systemd-resolved.service
systemctl is-enabled ssh.service
```

#### Step 2: Disable rpi-eeprom-update (saves ~575ms)
```bash
sudo systemctl stop rpi-eeprom-update.service
sudo systemctl disable rpi-eeprom-update.service
sudo systemctl disable rpi-eeprom-update.timer
sudo systemctl mask rpi-eeprom-update.service
```

#### Step 3: Create Post-RealDash Service
```bash
sudo tee /etc/systemd/system/post-realdash.service > /dev/null << 'EOF'
[Unit]
Description=Start non-critical services after RealDash
After=realdash.service
Wants=realdash.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'systemctl start systemd-networkd systemd-resolved ssh 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable post-realdash.service
```

#### Step 4: Make Network Services Start After RealDash
```bash
# systemd-networkd
sudo mkdir -p /etc/systemd/system/systemd-networkd.service.d
sudo tee /etc/systemd/system/systemd-networkd.service.d/after-realdash.conf > /dev/null << 'EOF'
[Unit]
After=realdash.service
EOF

# systemd-resolved
sudo mkdir -p /etc/systemd/system/systemd-resolved.service.d
sudo tee /etc/systemd/system/systemd-resolved.service.d/after-realdash.conf > /dev/null << 'EOF'
[Unit]
After=realdash.service
EOF

# SSH (if enabled)
sudo mkdir -p /etc/systemd/system/ssh.service.d
sudo tee /etc/systemd/system/ssh.service.d/after-realdash.conf > /dev/null << 'EOF'
[Unit]
After=realdash.service
EOF

sudo systemctl daemon-reload
```

#### Step 5: Optimize Journald (Optional - saves ~215ms)
```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/fastboot.conf > /dev/null << 'EOF'
[Journal]
Storage=volatile
EOF
```
**Note**: This makes logs RAM-only (lost on reboot), but eliminates journal flush delay.

#### Step 6: Verify Changes
```bash
# Check RealDash dependencies
systemctl show realdash.service | grep -E "^After=|^Wants="

# Check network services now depend on RealDash
systemctl show systemd-networkd.service | grep "^After="
systemctl show systemd-resolved.service | grep "^After="

# Verify post-realdash service
systemctl status post-realdash.service
```

#### Step 7: Reboot and Test
```bash
sudo reboot
```

After reboot, check boot time:
```bash
systemd-analyze blame | head -20
systemd-analyze critical-chain realdash.service
systemctl status post-realdash.service
```

## What This Does

### Before:
- RealDash, networking, SSH, and EEPROM checks all start in parallel
- Boot time: ~4.3 seconds total
- RealDash appears after all services finish

### After:
- RealDash starts first (only waits for essential services: udev, seatd, etc.)
- Network, SSH, DNS start **after** RealDash is already running
- EEPROM checks are disabled (you can run manually if needed)
- Boot time: RealDash appears faster, other services load in background

## Expected Boot Time Improvements

- **rpi-eeprom-update**: ~575ms saved (disabled)
- **systemd-networkd**: ~388ms deferred (starts after RealDash)
- **systemd-resolved**: ~324ms deferred (starts after RealDash)
- **systemd-journal-flush**: ~215ms saved (if using volatile storage)
- **ssh**: ~98ms deferred (starts after RealDash)

**Total potential savings**: ~1.6 seconds, but more importantly, **RealDash appears much sooner** because it doesn't wait for network/DNS/SSH.

## Troubleshooting

### If RealDash needs network immediately:
Remove the `After=realdash.service` dependency from network services:
```bash
sudo rm /etc/systemd/system/systemd-networkd.service.d/after-realdash.conf
sudo rm /etc/systemd/system/systemd-resolved.service.d/after-realdash.conf
sudo systemctl daemon-reload
```

### If you want to re-enable EEPROM updates:
```bash
sudo systemctl unmask rpi-eeprom-update.service
sudo systemctl enable rpi-eeprom-update.service
```

### Check what's blocking RealDash:
```bash
systemd-analyze critical-chain realdash.service
```

## For Future Builds

The `build_rpi5_fastboot.sh` script has been updated to automatically configure these optimizations. Future images built with the script will have these settings baked in.
