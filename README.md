# epicRPI

Scripts for setting up fast booting raspberry pi (target:5) for dashboard purposes

## hardware

The images are built from kernel up for specific hardware. It is imperative that the hardware is exactly the same, especially if precompiled images are being used.

[Raspberry Pi 5 8GB](https://a.co/d/7jMadcG) | [Raspberry Pi 5 Heatsink](https://a.co/d/elmmdVK) | [12v to 5v dc-dc converter](https://a.co/d/00Z0rZ2) | [Transcend ESD310 usb SSD](https://a.co/d/exShsKE) | [mcp2515 raspberry pi hat](https://a.co/d/3NRXKm7) | [BH1750 light sensor](https://a.co/d/2t3qrWY)

MIPI-DSI or HDMI display fitting your application. See [Adding your own MIPI display](#adding-your-own-mipi-display) below.

**CAN (EpicEFI):** Images ship with MCP2515 dtoverlay, `can0-up.service` (500 kbit/s SocketCAN), and `epicefi_verbose_can.xml` (Verbose 512–523 + custom CAN Outputs `0x500`–`0x507`). Assets under `realdash_scripts/epic-can/`. No userspace get_var bridge.

**USB keyboard and mouse** — required for first-time setup (WiFi, loading dashboards) and for RealDash edit mode. Touch alone is not enough for initial config.

## install

### precompiled image

Download: [content.epicefi.com/hostedfiles/epicRPI/](https://content.epicefi.com/hostedfiles/epicRPI/)

### build your own

In WSL:

```bash
git clone github.com/epicefi/epicrpi
cd epicrpi
```

The **`realdash_scripts`** directory contains the script for compiling RealDash images. For RealDash run:

```bash
./realdash_scripts/build_rpi5_fastboot.sh
```

Useful flags:

| Flag | Effect |
|------|--------|
| *(none)* | Full rebuild |
| `--skip-kernel` | Reuse existing kernel build |
| `--skip-rootfs` | Reconfigure existing rootfs only |
| `--quick` | Skip kernel and rootfs |
| `--console-only` | No RealDash/Xorg auto-start |
| `--rotate=left` | Override xrandr rotation (default: `left`) |

Output image: **`C:\rpi-fastboot\rpi5-fastboot.img`**. Flash with Rufus (DD mode) or Raspberry Pi Imager (custom OS).

For console-only image:

```bash
./console_only_build/build_rpi5_fastboot.sh
```

> **WSL tip:** The build script sets `DEBIAN_FRONTEND=noninteractive` so apt/gpg don’t prompt mid-run. For fewer sudo password prompts in WSL: `echo 'Defaults timestamp_timeout=480' | sudo tee /etc/sudoers.d/timeout && sudo chmod 440 /etc/sudoers.d/timeout`

**Clock:** Pi 5 has no battery RTC. The image is stamped with build time (`fake-hwclock`) and syncs via NTP once ethernet is up (`systemd-timesyncd`). No manual date step needed if the Pi gets network early — apt works after a few seconds on DHCP.

## SSH access

SSH is enabled with root login. Default credentials:

- **User:** `root`
- **Password:** `raspberry`

Connect via:

```bash
ssh root@<pi-ip-address>
```

To find the Pi's IP, either:

- Check your router/DHCP leases
- Connect a display and keyboard, log in, run `ip addr`
- Use mDNS: `ssh root@raspberrypi.local` (if your network supports it)

> **Note:** Root password login is enabled for convenience. For production, change the password with `passwd` and consider disabling root SSH or using key-based auth. SSH may be disabled at boot on some builds — start it with `systemctl start ssh` if needed.

## First boot — what you need

The Pi is meant to run headless in the car, but **first-time setup needs input and usually wired network**:

| Need | Why |
|------|-----|
| **USB keyboard** | RealDash has no on-screen keyboard; WiFi setup on tty2, VT switch (**Ctrl+Alt+F2**), and RealDash edit mode all need keys |
| **USB mouse** (recommended) | Easier than touch alone for RealDash menus, gallery, and dashboard editing |
| **Ethernet cable** (recommended first boot) | Sets clock via NTP, lets you SSH from a laptop, and is the easiest way to run `wifi-setup` before you unplug and mount in the car |

**Typical flow:** flash image → plug **keyboard + mouse + ethernet** → boot → **Ctrl+Alt+F2** → `wifi-setup "SSID" "password"` → confirm `wlan0` has an IP → unplug ethernet if you want WiFi-only → mount in vehicle.

Touch works on supported DSI panels after RealDash starts, but plan on a keyboard at least once for WiFi and dashboard loading.

## WiFi

New images ship with WiFi enabled (firmware + `wpa_supplicant` + `systemd-networkd` for `wlan0`). Bluetooth stays off.

### Connect (new image)

1. Boot with **ethernet plugged in** (wait ~10 s for DHCP and NTP).
2. Press **Ctrl+Alt+F2** for a root shell (fish).
3. Run:

```bash
wifi-setup "YOUR_SSID" "YOUR_PASSWORD"
ip addr show wlan0
ping -c 2 1.1.1.1
```

4. Optional: unplug ethernet and confirm WiFi still works after `ping -c 2 1.1.1.1`.

**Verify radio is up:**

```bash
ip link show wlan0
timedatectl          # clock synced? needed for apt
dmesg | grep brcmfmac
```

**Change network later:** run `wifi-setup` again with the new SSID/password, or edit `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` and `systemctl restart wpa_supplicant@wlan0`.

**No ethernet?** You can do everything on tty2 with keyboard + display: same `wifi-setup` command. Without any network on first boot, the clock may be wrong and apt can fail — plug ethernet briefly or run `date -s "YYYY-MM-DD HH:MM:SS"` before apt.

### SSH over WiFi

Once `wlan0` has an IP, from your laptop:

```bash
ssh root@<wlan-ip>
# or if mDNS works:
ssh root@raspberrypi.local
```

Default password: `raspberry`. SSH may need `systemctl start ssh` on some builds.

### Older image (WiFi was disabled at build time)

Run as root (fish-safe). Needs ethernet or a display once for the first setup.

```fish
# 1) Enable WiFi in boot config (comment out disable-wifi)
sed -i 's/^dtoverlay=disable-wifi/# dtoverlay=disable-wifi/' /boot/config.txt

# 2) Stop blacklisting the WiFi modules (keep BT blacklisted if you want)
rm -f /etc/modprobe.d/disable-wifi-bt.conf
printf '%s\n' 'blacklist bluetooth' 'blacklist btbcm' 'blacklist hci_uart' > /etc/modprobe.d/disable-bt.conf

# 3) Clock must be roughly correct or apt signature checks fail (new images: skip if timedatectl shows synced)
date
# only if wrong:
# date -s "2026-07-21 12:00:00"

# 4) RPi apt repo often fails SHA1 policy — disable it for this install
mv /etc/apt/sources.list.d/raspberrypi.list /etc/apt/sources.list.d/raspberrypi.list.disabled 2>/dev/null

# 5) Install firmware + client
apt-get update
apt-get install -y --allow-unauthenticated firmware-brcm80211 wireless-regdb iw wpasupplicant

# 6) DHCP for wlan0
printf '%s\n' '[Match]' 'Name=wlan0' '' '[Network]' 'DHCP=yes' > /etc/systemd/network/25-wlan.network

# 7) Reboot so the SDIO chip loads firmware cleanly
systemctl reboot
```

After reboot:

```fish
# confirm radio
dmesg | grep brcmfmac
ip link show wlan0

# associate (replace SSID/password)
wpa_passphrase "YOUR_SSID" "YOUR_PASSWORD" > /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
systemctl enable --now wpa_supplicant@wlan0
networkctl reload
networkctl up wlan0
ip addr show wlan0
ping -c 2 1.1.1.1
```

## TTY consoles

You can switch between virtual consoles on the attached display using **Ctrl+Alt+Fn**:

| Keys | TTY | Use |
|------|-----|-----|
| **Ctrl+Alt+F1** | tty1 | RealDash (Xorg) |
| **Ctrl+Alt+F2** | tty2 | Fish shell / config (auto-login) |
| Ctrl+Alt+F3 | tty3 | Extra shell |
| Ctrl+Alt+F4 | tty4 | Extra shell |
| Ctrl+Alt+F5 | tty5 | Extra shell |
| Ctrl+Alt+F6 | tty6 | Extra shell |

## BH1750 ambient light / auto-brightness

New RealDash images drive the **Waveshare panel backlight** from a BH1750 lux sensor (I2C). This is real backlight via `/sys/class/backlight/*/brightness` — **not** the old picom opacity workaround (that looked like contrast).

Hardware link: [BH1750 light sensor](https://a.co/d/2t3qrWY) (also listed under [hardware](#hardware)).

### Wiring

Connect the BH1750 to **I2C1** on the Pi 5 (same bus as `dtoverlay=i2c1` in the image):

| BH1750 | Pi 5 |
|--------|------|
| VCC | 3.3 V |
| GND | GND |
| SDA | GPIO2 (SDA1) |
| SCL | GPIO3 (SCL1) |
| ADDR | GND → address **0x23**; pull to 3.3 V → **0x5C** |

The build enables I2C, loads `bh1750` / `i2c-dev`, and `bh1750-sensor.service` tries both `0x23` and `0x5c` on boot.

### Verify the sensor

On **Ctrl+Alt+F2** (or SSH):

```bash
# needs i2c-tools: apt-get install -y i2c-tools
i2cdetect -y 1
# expect UU or 23 / 5c in the grid

lsmod | grep bh1750
ls /sys/bus/iio/devices/
cat /sys/bus/iio/devices/iio:device*/name
cat /sys/bus/iio/devices/iio:device*/in_illuminance_raw
```

Cover the sensor / shine a light — the raw value should change. If the sensor was plugged in after boot and is missing:

```bash
modprobe bh1750
echo bh1750 0x23 > /sys/bus/i2c/devices/i2c-1/new_device
# or:
echo bh1750 0x5c > /sys/bus/i2c/devices/i2c-1/new_device
```

### Manual backlight (sanity check)

```bash
ls /sys/class/backlight/
echo 25 > /sys/class/backlight/*/brightness    # dim
echo 255 > /sys/class/backlight/*/brightness   # bright (or use max_brightness)
cat /sys/class/backlight/*/brightness
cat /sys/class/backlight/*/max_brightness
```

If that changes panel brightness, auto-brightness can use the same path.

### Calibrate and run

```bash
auto-brightness setup    # interactive: low/high lux → backlight levels
auto-brightness start    # or: systemctl start auto-brightness
auto-brightness status
auto-brightness set 25   # constant level (stops auto); also: set 50%
auto-brightness stop
```

**Setup prompts:**

1. Cover sensor → Enter → choose backlight for dark (default **25**, range `0`–`max_brightness`, usually 0–255).
2. Bright light on sensor → Enter → choose backlight for bright (default **max**).
3. **Sample rate** (seconds) — how often to poll. Whole numbers or decimals (`1`, `0.5`, `0.25`).
4. **Averaging sample count** — integer only (e.g. `5`). Smooths flicker.

Config is saved to `/root/.config/auto-brightness.conf`. Enable on every boot after you’re happy with calibration:

```bash
systemctl enable --now auto-brightness
```

### Troubleshooting

| Symptom | Check |
|---------|--------|
| `auto-brightness` changes “contrast”, not backlight | Old picom-based script — replace `/usr/local/bin/auto-brightness` from `realdash_scripts/auto-brightness` (new builds already ship the sysfs version) |
| No I2C device | Wiring, `i2cdetect -y 1`, ADDR pin, `dmesg \| grep -i bh1750` |
| Sensor probe `-121` | Not connected / wrong address — try the other of `0x23` / `0x5c` |
| No `/sys/class/backlight/` | Panel backlight driver not bound — see Waveshare display section below |
| Daemon running but no change | `auto-brightness status`; confirm lux raw moves; re-run `setup` |

More low-level sensor notes: [`bh1750-sensor.md`](bh1750-sensor.md).

## RealDash

RealDash starts automatically on **tty1** at boot (`realdash.service`). Full manuals: **[RealDash Manuals & Tutorials](https://realdash.net/manuals.php)** — keyboard shortcuts: **[Keyboard Shortcuts](https://realdash.net/manuals/keyboard_shortcuts.php)**.

### Getting a dashboard on screen

1. Boot with **keyboard + mouse** (and ethernet for first-time WiFi).
2. RealDash opens on the MIPI/HDMI display (tty1).
3. **Shift+1** → Gallery → pick or download a dashboard (needs network for new downloads).
4. **Ctrl+O** → load a `.rdash` file from disk (edit mode).
5. **Ctrl+S** → save changes.

Dashboard files live under RealDash’s data directory (typically `/root/.local/share/RealDash/` or paths shown in RealDash **Settings**). Use a USB stick or SCP over SSH to copy `.rdash` files onto the Pi.

### Keyboard shortcuts (most used on the Pi)

**Run mode** (normal driving / display):

| Keys | Action |
|------|--------|
| **Arrow keys** | Switch dashboard pages |
| **Space** | Show / hide top menu |
| **Shift+1** | Gallery |
| **Shift+2** | Dyno |
| **Shift+3** | Log viewer |
| **Shift+4** | Profiles |
| **Shift+5** | Settings |
| **Shift+6** | Enter edit mode |
| **1–9** | Emulate steering-wheel buttons 1–9 |
| **F2** | Reboot RealDash app |
| **F4** | Fullscreen (desktop) |
| **F9** | Screenshot to gallery |

**Edit mode** (layout / gauges — use keyboard + mouse):

| Keys | Action |
|------|--------|
| **Ctrl+O** | Load dashboard |
| **Ctrl+S** | Save dashboard |
| **Ctrl+W** | Toggle hide all menus |
| **Ctrl+E** | Toggle edit bar |
| **Ctrl+R** | Rename |
| **Shift+7** | Exit edit mode |
| **Arrow keys** | Move selected gauges |
| **Del** | Delete selected gauges |

More shortcuts (align, scale, paste, etc.): [realdash.net/manuals/keyboard_shortcuts.php](https://realdash.net/manuals/keyboard_shortcuts.php)

### System commands (shell / SSH)

Run these from **Ctrl+Alt+F2**, SSH, or any tty except while typing inside RealDash:

```bash
systemctl status realdash    # is RealDash/X running?
systemctl restart realdash   # restart dashboard (fixes many glitches)
reboot                       # full Pi reboot (/usr/local/bin/reboot → systemctl)
poweroff                     # shut down

# optional — BH1750 panel auto-brightness (see section above)
auto-brightness setup
auto-brightness status
```

RealDash CAN, adapters, target IDs, multicast, etc.: see the [RealDash manuals index](https://realdash.net/manuals.php).

> **VT switch note:** Do **not** put `video=DSI-*:...rotate=` or `fbcon=rotate` in `/boot/cmdline.txt` when RealDash/Xorg runs on the same DSI. Kernel fb rotation freezes tty2 on a snapshot of tty1. Leave cmdline without rotate; landscape is done in X only (see Waveshare section). tty2 stays portrait — use SSH when you want a landscape shell.

## Working Waveshare 12.3" + RealDash (verified)

Target stack that works on Pi 5 + Waveshare **12.3-DSI-TOUCH-A** (DSI1 → shows as **DSI-2** in X):

| Layer | Working setting |
|-------|-----------------|
| **Kernel** | `rpi-6.12.y` (6.12+). Must include Waveshare V2 panel + Goodix drivers. A leftover **6.6** tree makes the panel blank even with the right overlay. |
| **config.txt** | `dtoverlay=vc4-kms-v3d-pi5` then `dtoverlay=vc4-kms-dsi-waveshare-panel-v2,12_3_inch_a_4lane`; `hdmi_force_hotplug=0` |
| **cmdline.txt** | **No** `video=` / **no** `fbcon=` rotate |
| **GUI** | RealDash under **Xorg** via `realdash.service` + `/root/.xinitrc` (not labwc) |
| **Display** | Native panel mode **720×1920**; landscape via `xrandr --output DSI-2 --mode 720x1920 --rotate left --primary` → **1920×720** |
| **Touch** | Goodix; apply matrix **after** RealDash starts (2s delay). Working matrix for `--rotate left`: `0 1 0 -1 0 1 0 0 1` + `xinput map-to-output … DSI-2` |
| **Packages** | Need **`xinput`** (separate from `x11-utils`), **`zenity`** (RealDash file dialogs), plus `x11-utils` / xrandr |

### `/root/.xinitrc` (known-good)

```sh
#!/bin/sh

xhost +local:

if command -v xsetroot >/dev/null 2>&1; then
  xsetroot -cursor_name left_ptr
fi

if command -v xset >/dev/null 2>&1; then
  xset -dpms
  xset s off
  xset s noblank
  xset m 0 0
fi

# Do not start classic unclutter: it grabs the pointer while the cursor is
# hidden, so a tap does nothing until you drag. RealDash needs tap-to-click.

xrandr --output DSI-2 --mode 720x1920 --rotate left --primary

# Start RealDash, then fix touch once X/RealDash are fully up
/usr/bin/realdash &
(
  sleep 2
  export DISPLAY=:0
  TOUCH_ID=$(xinput list | grep -i "goodix" | grep -o 'id=[0-9]*' | cut -d= -f2 | head -1)
  if [ -n "$TOUCH_ID" ]; then
    xinput set-prop "$TOUCH_ID" "Coordinate Transformation Matrix" 0 1 0 -1 0 1 0 0 1
    xinput map-to-output "$TOUCH_ID" DSI-2
  fi
) &

wait
```

### Lessons learned

1. **Blank 12.3" with HDMI working** — almost always wrong kernel branch (6.6 vs 6.12). Delete `~/rpi5-fastboot/sources/linux` and rebuild so the script reclones `rpi-6.12.y`.
2. **`xrandr --rotate` alone** orients RealDash; without `--rotate left` + landscape FB size, RealDash looks cropped in portrait 720×1920.
3. **Touch before RealDash starts** gets reset — delay touch calibration until after `/usr/bin/realdash` is running.
4. **`xinput` package** is required (`apt-get install -y xinput`). `x11-utils` alone is not enough.
5. **`zenity`** is required for RealDash file/open dialogs (`apt-get install -y zenity`). Without it, tinyfiledialogs errors on Unix.
6. **SSH + live `xinput`** needs `xhost +local:` in `.xinitrc` (and preferably `-auth /root/.Xauthority` on the Xorg line). Fish doesn’t use bash `$(...)` the same way — use `bash -c '...'` for one-liners.
7. **Kernel cmdline rotation breaks VT switch** with Xorg on the same DSI. Accept portrait tty2 or use SSH for config.
8. **Classic `unclutter -idle 5 -root`** swallows touch taps until the pointer moves. Do not start it from `.xinitrc`. If you still want a hidden cursor, use `unclutter -idle 5 -root -noevents` (or `unclutter-xfixes`) — not the default grab.

## Adding your own MIPI display

### Waveshare 12.3" DSI – what the working image uses (baseline)

A known-good image (RealDash on MIPI) was captured and used to align the build script. Important details:

- **Kernel**: **6.12+** (e.g. `6.12.66-v8-16k+`). The 12.3" panel needs the **waveshare-dsi** and **waveshare_touchscreen** drivers, which are in the Raspberry Pi **rpi-6.12.y** kernel. Older kernels (e.g. 6.6) only have the generic overlay and `panel-simple`, which can leave the display blank (dependency cycle, Goodix deferral).
- **config.txt**: `dtoverlay=vc4-kms-v3d-pi5` then `dtoverlay=vc4-kms-dsi-waveshare-panel-v2,12_3_inch_a_4lane`. **`hdmi_force_hotplug=0`** so the DSI panel is the primary display (console and GUI on tty1). With `hdmi_force_hotplug=1`, HDMI is forced and the DSI panel may not get the framebuffer.
- **Working dmesg**: `waveshare_touchscreen 11-0045`, `waveshare-dsi 1f00130000.dsi.0`, `Goodix-TS 11-005d` (touch), `rp1dsi_bind succeeded`, and **card2-DSI-2** under `/sys/class/drm/` with backlight at `11-0045`.

The build script clones **rpi-6.12.y**, adds the DSI overlay, sets **hdmi_force_hotplug=0**, installs RealDash under Xorg with the landscape/touch `.xinitrc` above, and leaves cmdline **without** kernel rotate.

### Test DSI on an already running install (Waveshare 12.3" DSI1)

Before changing the build script, enable the panel on the running Pi:

1. **SSH or console into the Pi** (e.g. `ssh root@raspberrypi.local`).

2. **Check that the overlay is present** (built from RPi kernel):
   ```bash
   ls /boot/overlays/vc4-kms-dsi-waveshare-panel-v2.dtbo
   ```
   If it’s missing, the image was built from a kernel that doesn’t include this overlay; you’ll need to add the overlay from the [Raspberry Pi firmware overlays](https://github.com/raspberrypi/firmware/tree/master/boot/overlays) or rebuild with the official RPi kernel that has it.

3. **Edit the boot config**:
   ```bash
   nano /boot/config.txt
   ```
   After the line `dtoverlay=vc4-kms-v3d-pi5` add (DSI1 is default, so no `,dsi0`):
   ```
   dtoverlay=vc4-kms-dsi-waveshare-panel-v2,12_3_inch_a_4lane
   ```
   Keep `dtoverlay=vc4-kms-v3d-pi5`; the manufacturer’s `vc4-kms-v3d` is the Pi 4 variant; on Pi 5 we use `vc4-kms-v3d-pi5`.

4. **Reboot** (use one that works on your system):
   ```bash
   systemctl reboot
```
   If that fails, try: `reboot` (works on images with `systemd-sysv`) or `shutdown -r now`

5. **If the screen is still blank**, use the checks below.

### Screen still blank – what to check

Use **HDMI** (or serial) to get a shell, then run these. Fix or note any errors.

**A. Kernel / DSI messages**
```bash
dmesg | grep -iE 'dsi|vc4|panel|waveshare|backlight|mipi'
```
- Look for probe success, “bound”, or errors (e.g. `panel-simple: failed to disable backlight: -110`, `i2c_designware: controller timed out`). I2C timeouts can mean backlight/panel init fails on Pi 5.

**B. DSI connector and mode**
```bash
cat /sys/kernel/debug/dri/0/state 2>/dev/null || true
# or list connectors (may need debugfs mounted)
ls /sys/class/drm/
```
- Check whether a DSI connector exists and is enabled.

**C. Backlight**
```bash
ls /sys/class/backlight/
cat /sys/class/backlight/*/brightness 2>/dev/null
cat /sys/class/backlight/*/max_brightness 2>/dev/null
```
- If a `backlight` device exists, try: `echo 255 | sudo tee /sys/class/backlight/*/brightness`. If there is no backlight node, the driver may not be binding (often I2C/backlight on Pi 5).

**D. config.txt**
- **Overlay order**: DSI panel overlay must be **after** `vc4-kms-v3d-pi5`. In `/boot/config.txt` you should have:
  - `dtoverlay=vc4-kms-v3d-pi5`
  - then `dtoverlay=vc4-kms-dsi-waveshare-panel-v2,12_3_inch_a_4lane`
- **HDMI**: If you only use DSI, try commenting out or removing `hdmi_force_hotplug=1` so the firmware doesn’t force HDMI; then reboot.
- **Wait**: Waveshare says the 12.3" can take ~30 seconds after power-on to show an image; wait once before assuming failure.

**E. Power**
- The 12.3" needs **5 V and ≥ 1 A** to the display (e.g. from the Pi’s 5 V/GPIO). Low current can cause no backlight or “display abnormality”.

**F. Hardware**
- DSI FFC: correct orientation (Waveshare: “FFC Cable 22PIN 200mm (opposite direction)”) and fully seated.
- If nothing in dmesg suggests DSI/panel probe, re-seat the DSI cable and reboot.

**G. Pi 5 / kernel**
- Some third-party DSI panels have backlight or I2C issues on Pi 5 with newer kernels. If you see backlight or I2C errors in dmesg, note your kernel version (`uname -r`) and consider asking Waveshare support or checking Raspberry Pi forums for your exact panel and kernel.

**H. If dmesg shows "Fixed dependency cycle" and "Cannot find any crtc or sizes" (no panel "bound")**

The overlay is loaded (dsi_panel@0 exists) but the panel driver may not be probing or vc4 isn’t getting a CRTC. Run these and keep the output:

1. **Panel driver and deferred probe**
   ```bash
   dmesg | grep -iE 'panel|deferred|1f00130000|bound|probe'
   ```
   Look for `panel-simple`, `deferred probe`, or bind/probe messages for the DSI panel.

2. **DRM connectors**
   ```bash
   ls -la /sys/class/drm/
   cat /sys/class/drm/card*/status 2>/dev/null
   ```
   If there is no `card0-DSI-*` (or similar), the DSI connector never registered.

3. **Try DSI0 instead of DSI1**  
   In `/boot/config.txt`, change the overlay line to use DSI0:
   ```
   dtoverlay=vc4-kms-dsi-waveshare-panel-v2,12_3_inch_a_4lane,dsi0
   ```
   Reboot and test. Some setups work on one port only.

4. **Kernel config (if you built the kernel)**  
   The overlay expects the generic panel driver. On the **build machine** (where you compile the image), check that the kernel has:
   ```bash
   zcat /proc/config.gz 2>/dev/null | grep -E 'DRM_PANEL_SIMPLE|DRM_RP1_DSI' || true
   ```
   On the Pi, if you have the kernel source: `grep -E 'CONFIG_DRM_PANEL_SIMPLE|CONFIG_DRM_RP1_DSI' /path/to/linux/.config`.  
   If `CONFIG_DRM_PANEL_SIMPLE` is `=m`, ensure the module is loaded: `sudo modprobe panel_simple`.

5. **Pi 5 firmware**  
   Some report DSI works better with a specific EEPROM/firmware. Optional: `sudo rpi-eeprom-update` (if rpi-eeprom is installed) and reboot; or try the [Waveshare pre-installed image](https://www.waveshare.com/wiki/12.3-DSI-TOUCH-A) on the same hardware to confirm the panel works.

**I. If you see no DSI connector in `/sys/class/drm/` and `i2c 11-005d: deferred probe pending`**

- **card2** only shows HDMI-A-1, HDMI-A-2 and no **card2-DSI-*** → the DSI panel never registered with DRM.
- **No `/sys/class/backlight/`** → the panel driver didn’t probe (so no backlight device).
- **`Goodix-TS 11-005d: ... deferred probe pending`** → the **Goodix touch controller** at 0x5d on bus 11 (i2c_csi_dsi) is deferring; that can affect probe order and prevent the panel from coming up.

Do this next:

1. **Try with touch disabled** (so Goodix doesn’t probe/defer and the panel can come up first).  
   In `/boot/config.txt`, change the overlay line to add **`disable_touch`**:
   ```
   dtoverlay=vc4-kms-dsi-waveshare-panel-v2,12_3_inch_a_4lane,disable_touch
   ```
   Reboot. If the display and backlight work, touch was blocking probe order; you can then try removing `disable_touch` and see if a firmware/kernel update fixes Goodix later.

2. **Optional: see what’s on I2C bus 11**  
   `i2cdetect` is in the **i2c-tools** package. Install and run (use `bash` if your shell doesn’t run multiple commands):
   ```bash
   apt-get install -y i2c-tools
   i2cdetect -y 11
   ```
   You should see 0x45 (panel) and often 0x5d (Goodix touch); 0x14 may also appear depending on overlay.

3. **Load the panel driver if it’s a module**
   ```bash
   sudo modprobe panel_simple
   dmesg | tail -20
   ```
   If the panel then binds, you should see a new connector and possibly `/sys/class/backlight/`.

4. **Confirm panel with Waveshare image**  
   Flash the [Waveshare 12.3" pre-installed image](https://www.waveshare.com/wiki/12.3-DSI-TOUCH-A) on the same SD/USB and same hardware. If the display works there, the issue is your kernel/build or firmware, not the panel or cable.

---

The default build is intended for a Waveshare 12.3" DSI panel; the build script can be updated to add the overlay to `config.txt` once this works. To use a different MIPI-DSI display:

1. **Visit your vendor's site** (e.g. Waveshare, Kuman, etc.) and find the Pi 5–compatible overlay and any panel-specific files.
2. **Identify the overlay name** (e.g. `vc4-kms-dsi-waveshare-panel-v2`) and parameters (e.g. `12_3_inch_a_4lane`).
3. **Edit the boot config** on the Pi's boot partition (`/boot/config.txt`):
   - Replace the existing `dtoverlay=vc4-kms-dsi-*` line with your panel's overlay.
   - Example for a different panel:
     ```
     dtoverlay=vc4-kms-dsi-<vendor-panel-name>,<panel-param>
     ```
4. **If the vendor provides a `.dtbo` file**, copy it to `/boot/overlays/` on the boot partition.
5. **To bake it into the image**, edit `build_rpi5_fastboot.sh` in the `config.txt` block where the overlays and options are set:
   - Change the `dtoverlay=vc4-kms-dsi-waveshare-panel-v2,12_3_inch_a_4lane` line to your overlay.
   - Add any vendor-provided `.dtbo` files into the overlays directory before creating the image.
6. **Reboot** after changes and verify the display works before adjusting other settings.

Keep `dtoverlay=vc4-kms-v3d-pi5`; it is required for Pi 5 graphics.

## Fact-finding on a working Pi (baseline for the build)

When you have a **working** image (e.g. RealDash on the MIPI display), run these over SSH and save the output so the build script and kernel can be matched to this baseline.

**1. Kernel and OS**
```bash
uname -r
cat /etc/os-release 2>/dev/null || true
```

**2. Boot config (DSI overlays and order)**
```bash
cat /boot/config.txt
# If you use split config:
ls /boot/config.d/ 2>/dev/null; for f in /boot/config.d/*.conf; do echo "=== $f ==="; cat "$f" 2>/dev/null; done
```

**3. DSI / VC4 / panel / touch in dmesg**
```bash
dmesg | grep -iE 'dsi|vc4|panel|waveshare|backlight|mipi|goodix|bound|deferred'
```

**4. DRM connectors and backlight**
```bash
ls -la /sys/class/drm/
ls -la /sys/class/backlight/ 2>/dev/null || echo "(no backlight dir)"
cat /sys/class/backlight/*/brightness 2>/dev/null
cat /sys/class/backlight/*/max_brightness 2>/dev/null
```

**5. Kernel config (if present)**
```bash
zcat /proc/config.gz 2>/dev/null | grep -E 'DRM_PANEL|DRM_VC4|DRM_RP1|GOODIX' || true
```

**6. Firmware / EEPROM**
```bash
vcgencmd version 2>/dev/null || true
rpi-eeprom-update 2>/dev/null || true
ls -la /boot/*.dtb /boot/overlays/vc4*.dtbo /boot/overlays/*waveshare*.dtbo 2>/dev/null
```

**7. One-liner to save everything to a file**
```bash
{ echo "=== uname ==="; uname -a; echo "=== os-release ==="; cat /etc/os-release 2>/dev/null; echo "=== config.txt ==="; cat /boot/config.txt; echo "=== dmesg dsi/vc4/panel ==="; dmesg | grep -iE 'dsi|vc4|panel|waveshare|backlight|goodix|bound|deferred'; echo "=== drm ==="; ls -la /sys/class/drm/; echo "=== backlight ==="; ls -la /sys/class/backlight/ 2>/dev/null; echo "=== kernel config snippet ==="; zcat /proc/config.gz 2>/dev/null | grep -E 'DRM_PANEL|DRM_VC4|DRM_RP1|GOODIX' || true; } | tee /root/working-pi-baseline.txt
```
Then copy `/root/working-pi-baseline.txt` off the Pi (e.g. `scp root@rpi5:/root/working-pi-baseline.txt .`).

