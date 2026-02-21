# epicRPI

Scripts for setting up fast booting raspberry pi (target:5) for dashboard purposes

## hardware

The images are built from kernel up for specific hardware. It is imperative that the hardware is exactly the same, especially if precompiled images are being used.

[Raspberry Pi 5 8GB](https://a.co/d/7jMadcG) | [Raspberry Pi 5 Heatsink](https://a.co/d/elmmdVK) | [12v to 5v dc-dc converter](https://a.co/d/00Z0rZ2) | [Transcend ESD310 usb SSD](https://a.co/d/exShsKE) | [mcp2515 raspberry pi hat](https://a.co/d/3NRXKm7) | [BH1750 light sensor](https://a.co/d/2t3qrWY)

MIPI-DSI or HDMI display fitting your application. See [Adding your own MIPI display](#adding-your-own-mipi-display) below.

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

For console-only image:

```bash
./console_only_build/build_rpi5_fastboot.sh
```

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

> **Note:** Root password login is enabled for convenience. For production, change the password with `passwd` and consider disabling root SSH or using key-based auth.

## TTY consoles

You can switch between virtual consoles on the attached display using **Ctrl+Alt+Fn**:

| Keys | TTY | Use |
|------|-----|-----|
| **Ctrl+Alt+F1** | tty1 | Main console (RealDash/GUI or login) |
| **Ctrl+Alt+F2** | tty2 | Shell / auto-brightness setup, config |
| Ctrl+Alt+F3 | tty3 | Extra shell |
| Ctrl+Alt+F4 | tty4 | Extra shell |
| Ctrl+Alt+F5 | tty5 | Extra shell |
| Ctrl+Alt+F6 | tty6 | Extra shell |

To configure auto-brightness, press **Ctrl+Alt+F2** to reach TTY2, log in, then run:

```bash
auto-brightness setup
```

## Adding your own MIPI display

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
   sudo reboot
   ```
   If that fails, try: `systemctl reboot` or `sudo shutdown -r now`

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
5. **To bake it into the image**, edit `build_rpi5_fastboot.sh` (around line 1193) where `config.txt` is generated:
   - Change the `dtoverlay=vc4-kms-dsi-waveshare-panel-v2,12_3_inch_a_4lane` line to your overlay.
   - Add any vendor-provided `.dtbo` files into the overlays directory before creating the image.
6. **Reboot** after changes and verify the display works before adjusting other settings.

Keep `dtoverlay=vc4-kms-v3d-pi5`; it is required for Pi 5 graphics.
