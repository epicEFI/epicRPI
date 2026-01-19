# epicRPI

Scripts for setting up fast booting raspberry pi (target:5) for dashboard purposes

not to be confused with pidash
#
u: root

pw: raspberry

run the script in wsl, flash the resulting image with rufus

systemctl start ssh

you are sudo, sudo doesn't exist

# Hardware support

This is tested hardware, tested to boot in <10 seconds. It is IMPERATIVE that you use the same hardware, as these images are built to optimize for boot times and have limited drivers installed.

raspberry pi 5 8GB (4GB will be ok) [link](https://a.co/d/1PXSXdL)

Transcend ESD310 usb 3.0 SSD [link](https://a.co/d/cW80QCR)

22 pin MIPI-DSI display that fits your car, and budget. (15 pin with an adapter works too) HDMI screens work as well but will delay boot time by ~2 seconds

CMOS battery [link](https://a.co/d/0xDBMn7)

Automotive 5v/5a Power supply [link](https://a.co/d/cKBloN2)

Heatsink [link](https://a.co/d/0n9e4wC)

Light Intensity sensor, optional [link](https://a.co/d/19SxmkF)

CAN Hat, optional [link](https://a.co/d/8DmYPRs)

