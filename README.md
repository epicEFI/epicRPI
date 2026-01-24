# epicRPI

Scripts for setting up fast booting raspberry pi (target:5) for dashboard purposes

## hardware

The images are built from kernel up for specific hardware. It is imperative that the hardware is exactly the same, especially if preocmpiled images are being used

[Raspberry Pi 5 8GB](https://a.co/d/7jMadcG)

[Raspberry Pi 5 Heatsink](https://a.co/d/elmmdVK)

[12v to 5v dc-dc converter](https://a.co/d/00Z0rZ2)

[Transcend ESD310 usb SSD](https://a.co/d/exShsKE)

[mcp2515 raspberry pi hat](https://a.co/d/3NRXKm7)

[BH1750 light sensor](https://a.co/d/2t3qrWY)

## install

### precompiled image

placeholder

### build your own

in wsl:

git clone github.com/epicefi/epicrpi

for realdash run:

```bash

./build_rpi5_fastboot.sh

```

for console only image run:

```bash

./console_only_build/build_rpi_fastboot.sh

```

not to be confused with pidash
