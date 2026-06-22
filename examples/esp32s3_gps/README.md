# NMEA GPS receiver — a task-driven Ada UART driver (ESP32-S3, no FreeRTOS)

Demo for the reusable **`ESP32S3.GPS`** driver (in `libs/esp32s3_hal`). Unlike
the passive I2C device drivers, this is a **singleton background service**: a
library-level task owns a UART, continuously reads the receiver's NMEA stream,
decodes it, and publishes the results into a **protected store** the application
reads. No `Device` handle — the package *is* the device.

```
[gps] gga accept  : PASS      [gps] vtg vel     : PASS
[gps] position    : PASS      [gps] gsv view    : PASS
[gps] fix info    : PASS      [gps] gsa dop     : PASS
[gps] utc time    : PASS      [gps] bad-cks rej : PASS
[gps] rmc accept  : PASS
[gps] date        : PASS
[gps] velocity    : PASS
[gps] zda t/date  : PASS
[gps] gll pos     : PASS
[gps] live (UART0 @ 9600) -- waiting for sentences...
[gps] UTC=19:57:13 view=10 snr=24 no-fix          <- acquiring (GSV/GSA)
[gps] raw: $GPGSV,3,1,10,05,10,088,,10,28,296,24,...
   ... once it locks ...
[gps] UTC=19:57:27 lat=33.9733503 lon=-84.3321415  <- 3D fix
[gps] raw: $GNGSA,A,3,10,15,18,23,24,,,,,,,,3.6,1.9,3.1,1*35
```

## Wiring (UART0; all three pins optional, only Rx is needed to receive)

| receiver | ESP32-S3 | notes |
|---|---|---|
| TXD | **GPIO44** (U0RXD) | data **in** from the GPS — the one line you must wire |
| RXD | **GPIO43** (U0TXD) | data **out** to the GPS (config commands; routed, send is a follow-up) |
| 1PPS | *optional* | a GPIO interrupt, timestamped for time alignment (unset here) |
| VCC / GND | 3V3 / GND | |

UART0's pads are free here because the console is USB-Serial-JTAG. Most modules
default to **9600 baud**, 1 Hz NMEA.

## What it does

| phase | how | proves |
|---|---|---|
| **self-test** | `Inject` canned GGA / RMC / ZDA / GLL / VTG (and one bad checksum) **before** `Setup` — reader task still suspended, store quiescent | decoding, the paired-`Position` store, per-field timestamps, and checksum rejection — all on silicon, no live receiver needed |
| **live** | `Setup` UART0 and release the reader task; once a second print the UTC clock + latest fix | real reception: the clock ticks from live ZDA/RMC even with no position lock |

Decoded sentences: **GGA** (fix, position, altitude, satellites), **RMC**
(position, validity, velocity, date/time), **ZDA** (UTC time + date, *not* gated
on a fix), **GLL** (position + time), **VTG** (velocity), **GSV** (satellites in
view + C/N0), **GSA** (2D/3D mode + dilution of precision). Talker-agnostic
(`GP`/`GN`/`GL`/`BD`/…); checksum is mandatory; anything else is ignored.

`Satellites_In_View` returns the full per-satellite list (system + PRN +
elevation + azimuth + C/N0), accumulated across GSV messages and constellations
and aged out, so a satellite that drops out of the stream disappears. The demo
dumps it every 10 s:

```
[gps] satellites in view: 13
[gps]   GP18 el=76 az=164 snr=27
[gps]   GP24 el=51 az=98 snr=27
   ...
[gps]   BD13 el=56 az=265 snr=23   (snr=0 = in view but not tracked)
```

## Design points

- **No board pins in the driver.** The wiring is stated in `src/main.adb` and
  handed to `Setup`, which records it and brings the UART up.
- **No torn data.** Every value is read/written under one protected lock;
  Latitude+Longitude are one `Position` record set in a single action, so a fix
  is always a consistent pair.
- **Staleness.** Each value group carries an `Updated_At` timestamp; the driver
  refreshes a group only from a *valid* sentence (a lost fix is not written), so
  a stale group keeps its old timestamp. Compare `Age (R.Updated_At)` against
  your tolerance. (The demo shows a leftover self-test position aging out of the
  3 s freshness window into `no-fix`.)
- **Reader priority.** The reader task runs *below* application priority — at
  equal priority, with data always available, it would never yield. This is set
  in the driver (`System.Default_Priority - 1`).
- **`Last_Sentence`** copies the most recent raw NMEA line out — handy for
  diagnosing a quiet or unlocked receiver (this is the `raw:` echo).

## Build / flash / run

```sh
./x build gps            # -> app.bin (embedded profile)
./x flash gps -p /dev/ttyACM0
./x run   gps -p /dev/ttyACM0    # build + flash + serial monitor (115200)
```

## Getting an actual position fix

Indoors a cold module emits ZDA/RMC with **no fix** (empty position, status `V`),
so you'll see the UTC clock tick and the acquisition view (`view=N snr=N`) climb
as satellites appear. Give the antenna sky view (window / outside) for a minute;
once it locks, GGA/RMC/GLL arrive with a fix and a fresh `lat=…  lon=…` prints.
(`$GPTXT,…,ANTENNA OK` in the raw echo confirms the antenna path is healthy.)

## L76K-specific commands (PCAS)

The generic driver is receive-only NMEA. The **`ESP32S3.GPS.L76K`** child adds
the Quectel L76K's proprietary **PCAS** configuration commands — it *sends*
sentences to the receiver (via `ESP32S3.GPS.Send` and a routed Tx pin). The
package itself is the "L76K only" gate: `with` it only when the module is an L76K.

| command | procedure | status |
|---|---|---|
| PCAS04 | `Set_Constellation` (GNSS selection) | **tested** |
| PCAS01 | `Set_Baud_Rate` | coded, untested |
| PCAS02 | `Set_Update_Rate` | coded, untested |
| PCAS03 | `Set_NMEA_Output` | coded, untested |
| PCAS10 | `Restart` | coded, untested |

The demo tests **PCAS04** live: after the default GPS+BeiDou baseline it enables
**all** constellations, and the satellite dump grows to include GLONASS —

```
[gps] satellites in view: 10      (7 GPS + 3 BeiDou, default)
[gps] >> PCAS04: set GNSS = GPS+BeiDou+GLONASS
   ... GLONASS acquires (give it ~1 min from cold) ...
[gps] satellites in view: 17
[gps]   GP24 el=49 az=71 snr=27
[gps]   BD13 el=50 az=239 snr=22
[gps]   GL84 el=35 az=180 snr=25   <- GLONASS now in view
```

— proving the command is framed, checksummed, transmitted, and acted on.
Disabling a constellation is instant; *enabling* GLONASS means acquiring those
satellites from scratch, so it appears in the dumps a while later.

## Notes

- The same bare ROM-`printf` caveats as the other examples (no `+` flag,
  ~6-conversion cap, non-blocking 64-byte FIFO): the sample line is built into a
  buffer and kept under 64 bytes, and back-to-back lines are spaced.
- Uses the controlled UART `Session` + a task + protected objects, so like the
  other Session drivers it targets the **embedded / full** profiles, not
  light-tasking.
