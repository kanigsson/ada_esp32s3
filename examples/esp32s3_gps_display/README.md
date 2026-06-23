# GPS on an ST7789 display — a bare-metal Ada demo (ESP32-S3)

Combines **two** reusable HAL drivers to show a live GPS fix on a screen:

- **`ESP32S3.GPS`** — task-driven NMEA receiver on UART0. A background task
  decodes the receiver's stream into a protected store; the app just reads the
  latest snapshot.
- **`ESP32S3.ST7789`** + **`.Text`** — 240×240 SPI panel and the 5×7 font layer.

Once a second it reads `Current_Time` / `Current_Position` / `Current_Fix` and
paints UTC, latitude, longitude and fix status onto the panel.

```
[gps-disp] --- tick 2 ---
[gps-disp] UTC 03:39:13
[gps-disp] Lat 33.9724095 N
[gps-disp] Lon 084.3318140 W
[gps-disp] Fix 3D Sat 08
[gps-disp] * fix live
```

The panel is the real output — the console mirrors each row pushed to it so a
live run can be checked over serial too (the display is write-only).

## On-screen layout (240×240)

```
GPS                 <- title, 3x green
UTC 03:39:13        <- live UTC (from RMC/GGA/ZDA)
Lat 33.9724095 N    <- latitude,  signed 1e-7 deg -> DD.DDDDDDD + hemisphere
Lon 084.3318140 W   <- longitude, same, 3 integer digits
Fix 3D Sat 08       <- GSA solution mode + satellites used in the GGA fix
* fix live          <- green when the fix is fresh, amber "* searching" otherwise
```

Each value row is rendered at scale 2 and **padded to a fixed width**, so each
opaque redraw overwrites the previous value (the panel is write-only — there's
no framebuffer to clear selectively).

## Two drivers, one core, no contention

The GPS reader is a background task on UART0; the display is driven from `Main`
on SPI2. They share nothing: different peripherals, different pins. The display
`Session` is **held for the whole run** (so no other task can corrupt the
controller) while each text update locks the SPI host only for its own
transfers — the driver's two-level locking. Reads from the GPS store are
consistent snapshots (latitude/longitude are one atomically-updated record).

## Wiring

| Signal | ESP32-S3 | notes |
|---|---|---|
| GPS TXD → | **IO44** (U0RXD) | NMEA in from the receiver |
| → GPS RXD | **IO43** (U0TXD) | out to the receiver (config; unused here) |
| LCD SCLK | **IO12** | SPI2 clock |
| LCD MOSI | **IO13** | SPI2 data (write-only) |
| LCD DC | **IO16** | data/command |
| LCD CS | **IO10** | chip select |
| LCD BLK | **IO6** | backlight — driven by the example, not the driver |
| LCD RST | *not wired* | software reset |

GPS at 9600 baud (the L76K default). The USB-Serial-JTAG console coexists with
UART0, so you get both the panel and the serial mirror.

## Build / flash / run

```sh
./x build gps_display            # -> app.bin (embedded profile)
./x flash gps_display -p /dev/ttyACM0
./x run   gps_display -p /dev/ttyACM0
```

Needs a GPS antenna with sky view to lock. Until a fix arrives the rows show
`--` placeholders and the status line reads `* searching`; UTC can appear before
the position fix (ZDA/RMC time updates aren't gated on a lock).

## Notes

- The "satellites" figure is `Fix.Satellites` (used in the GGA solution) — stable,
  unlike the per-constellation GSV *in-view* count which jumps as each
  constellation's GSV arrives.
- Both drivers use controlled `Session`s / a task, so this targets the
  **embedded / full** profiles, not light-tasking.
