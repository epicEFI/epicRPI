fatload mmc 0:1 ${kernel_addr_r} kernel8.img
fatload mmc 0:1 ${fdt_addr_r} bcm2712-rpi-5-b.dtb
setenv bootargs "console=tty1 console=ttyS0,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/lib/systemd/systemd"
booti ${kernel_addr_r} - ${fdt_addr_r}
