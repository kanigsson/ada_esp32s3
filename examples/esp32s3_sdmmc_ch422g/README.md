# SD card via SDMMC with a CH422G-driven DAT3 — bare-metal Ada (ESP32-S3)

Reads an SD card in **1-bit SDMMC mode** on a board where the card's **DAT3/CD**
line is not wired to the SoC but to a **CH422G** I2C expander pin. Two reusable
HAL drivers together: `ESP32S3.CH422G` holds DAT3 high (so the card enters/stays
in SD mode), and `ESP32S3.SDMMC` talks to the card on CLK/CMD/D0.

```
[sd] SD card via SDMMC 1-bit, DAT3/CD held high by CH422G IO4
[sd]   SDMMC: CLK=IO12 CMD=IO11 D0=IO13   CH422G: I2C0 SDA=8 SCL=9
[sd] CH422G IO bank -> 0x10 (DAT3 high) : OK
[sd] init: OK   card: SDHC/SDXC
[sd] read block 0: OK   first bytes = 00 00 00 00   boot sig 0x55AA: present
```

**Read-only:** it identifies the card and reads block 0 (checking the 0x55AA boot
signature). It never writes — no card content can be lost.

## Wiring

| SD pin | Connected to | role (1-bit SD mode) |
|---|---|---|
| CLK | **IO12** | SDMMC clock |
| CMD | **IO11** | command line |
| DAT0 | **IO13** | the single data line |
| DAT1 / DAT2 | — | unused in 1-bit mode |
| **CD / DAT3** | **CH422G IO4** | held **high** to select the card |

In 1-bit mode DAT3 is not a host data line; the card samples it at its first
command (high → SD mode) and it must stay high. It's set **once** and never
toggled during transfers, so driving it from the slow I2C expander is fine.

## Sequence

1. **CH422G**: load its IO output register with `0x10` (IO4 = 1, every other IO
   low — per this board), *then* enable outputs, so DAT3 is high the instant the
   bank switches to outputs (no glitch). The expander's IO direction is global,
   so making IO4 an output makes all of IO0–7 outputs; the value drives IO4 high
   and the rest low.
2. **SDMMC**: `Setup` on Slot1, 1-bit (`Width_1`, D1/D2/D3 = No_Pin), then
   `Initialize` and `Read_Block (0)`.

## Build / flash / run

```sh
./x build sdmmc_ch422g
./x flash sdmmc_ch422g -p /dev/ttyACM0
./x run   sdmmc_ch422g -p /dev/ttyACM0
```

## Notes

- **This example surfaced a real bug in `ESP32S3.SDMMC`**, fixed alongside it: the
  driver's controller-poll loops were *iteration-count* bounded, and at `-O2`
  those tight loops expired in microseconds — long before a command response or
  data word arrived. Identification only *appeared* to work (the driver read the
  response register later, after other code gave the hardware time); the data
  read, gated on the command-done flag, timed out. The loops are now bounded by a
  real-time (`Ada.Real_Time`) deadline, independent of CPU speed / optimisation.
  Verified reading at the full 20 MHz data clock.
- Both drivers use controlled / protected resources, so this targets the
  **embedded / full** profiles.
- Pull-ups (~10 kΩ) on CMD/DAT0 are assumed on the board.
