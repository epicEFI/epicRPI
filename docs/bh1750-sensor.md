# BH1750 Light Sensor Documentation

## Overview
The BH1750 is an I2C light sensor that measures illuminance. This document covers how to use it on the Raspberry Pi 5.

## Setup

### 1. Enable I2C
I2C is enabled in the build script via `dtoverlay=i2c1` in `config.txt`. The `i2c-dev` module is automatically loaded.

### 2. Load BH1750 Driver
The driver is compiled into the kernel. Load it with:
```bash
sudo modprobe bh1750
```

To auto-load on boot, add to `/etc/modules`:
```bash
echo "bh1750" | sudo tee -a /etc/modules
```

## Hot-Plugging the Sensor

When you connect the sensor after boot, you need to manually add it to the I2C bus:

```bash
# Add bh1750 sensor at address 0x23 to I2C bus 1
echo bh1750 0x23 | sudo tee /sys/bus/i2c/devices/i2c-1/new_device
```

**Note:** Some modules use address 0x5C instead. If 0x23 doesn't work, try:
```bash
echo bh1750 0x5C | sudo tee /sys/bus/i2c/devices/i2c-1/new_device
```

## Reading Sensor Values

### Check if Sensor is Detected
```bash
# Verify device exists
ls -la /sys/bus/i2c/devices/ | grep 0023

# Check IIO device name
cat /sys/bus/iio/devices/iio:device0/name
# Should output: bh1750
```

### Read Raw Illuminance Value
```bash
cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw
```

**Output:** Raw sensor value (typically ranges from single digits in darkness to thousands in bright light)

### Continuous Monitoring
```bash
# Watch values update every second
watch -n 1 'cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw'
```

### Convert to Lux (Optional)
The raw value can be converted to lux by dividing by 1.2:
```bash
RAW=$(cat /sys/bus/iio/devices/iio:device0/in_illuminance_raw)
LUX=$(awk "BEGIN {printf \"%.2f\", $RAW / 1.2}")
echo "Raw: $RAW, Lux: ${LUX} lx"
```

## File Paths

- **Device path:** `/sys/bus/i2c/devices/1-0023/`
- **IIO device:** `/sys/bus/iio/devices/iio:device0/`
- **Raw illuminance:** `/sys/bus/iio/devices/iio:device0/in_illuminance_raw`
- **Device name:** `/sys/bus/iio/devices/iio:device0/name`

## Troubleshooting

### Check I2C Bus
```bash
# Scan I2C bus for devices
sudo i2cdetect -y 1
# Should show "23" or "5C" if sensor is connected
```

### Check if Driver is Loaded
```bash
lsmod | grep bh1750
```

### Check dmesg for Errors
```bash
dmesg | grep -i bh1750
dmesg | grep -i i2c
```

### Remove and Re-add Device
```bash
# Remove device
echo 0x23 | sudo tee /sys/bus/i2c/devices/i2c-1/delete_device

# Re-add device
echo bh1750 0x23 | sudo tee /sys/bus/i2c/devices/i2c-1/new_device
```

## Build Script Configuration

The build script includes:
- I2C kernel support (`CONFIG_I2C`, `CONFIG_I2C_CHARDEV`)
- BH1750 driver (`CONFIG_BH1750`)
- IIO subsystem (`CONFIG_IIO`, `CONFIG_IIO_BUFFER`, `CONFIG_IIO_KFIFO_BUF`)
- I2C device tree overlay (`dtoverlay=i2c1` in config.txt)
- Auto-loading `i2c-dev` module

## Notes

- The sensor must be manually added to the I2C bus when hot-plugged
- The device number (iio:device0) may vary if other IIO devices are present
- Raw values are sufficient for most use cases; conversion to lux is optional
- Address 0x23 is the default; some modules use 0x5C
