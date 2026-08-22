# SocketCAN + RealDash CAN XML for EpicEFI

Shipped into the RealDash image by `build_rpi5_fastboot.sh`.

| File | Install path |
|------|----------------|
| `can0-up.sh` | `/usr/local/sbin/can0-up.sh` |
| `can0-up.service` | `/etc/systemd/system/can0-up.service` |
| `epicefi_verbose_can.xml` | `/root/Documents/RealDash/settings/` and `/root/.local/share/realdash/` |

## Boot order

1. `can0-up` — `ip link` at 500 kbit/s (do **not** use systemd-networkd CAN netdevs)
2. `realdash` — `After=` / `Requires=` `can0-up.service`

## Protocol (listen / decode only)

- **Verbose CAN** IDs 512–523 from rusEFI DBC
- **Custom CAN Outputs** IDs 1280–1287 (`0x500`–`0x507`) from TunerStudio
- No userspace get_var / epic-bridge

Keep `epicefi_verbose_can.xml` in sync with the mr2RD project (`dbc_to_realdash_verbose.py`).
