# SHT41 temperature/humidity — a bare-metal Ada I2C driver (ESP32-S3)

Demo for the reusable **`ESP32S3.SHT41`** sensor driver (in `libs/esp32s3_hal`).
Same shape as the RTC/IMU drivers — a `Device` set up with the I2C wiring, each
operation opening a short-lived, auto-released `ESP32S3.I2C` `Session` — so the
Sensirion SHT41 shares the bus safely with the other I2C devices. No interrupt:
it is simply read on request.

```
[sht] SHT41 temperature/humidity driver demo (SDA=IO8 SCL=IO7)
[sht] serial : 0x10ce099e  (SHT41 present)
[sht] T=26.78 C  RH=38.00 %
[sht] T=26.79 C  RH=38.08 %
   ... one reading per second ...
```

## Wiring

| SHT41 | ESP32-S3 | notes |
|---|---|---|
| SDA | **IO8** | I2C0 data (shared bus) |
| SCL | **IO7** | I2C0 clock (shared bus) |
| VDD / VSS | 3V3 / GND | |

The SHT41-AD1B answers at I2C address **0x44**. It coexists on the same bus with
the PCF85063A RTC (0x51) and QMI8658C IMU (0x6B) — each driver takes the I2C
host's `Session` per operation, so they serialise automatically.

## What it does

| step | driver call | proves |
|---|---|---|
| `probe` | `Read_Serial_Number` | the sensor ACKs and its serial-number words pass CRC (a comms check) |
| `sample` | `Measure` | a high-precision T+RH measurement once a second |

The SHT4x is **command-based** (no registers): `Measure` writes a 1-byte command,
waits the conversion time (~8 ms high / ~4 ms medium / ~2 ms low), reads 6 bytes
(temperature word + CRC, humidity word + CRC), checks both **CRC-8**s, and
converts to integer milli-units (`Measurement.Temperature` in m°C,
`.Humidity` in m%RH) — no float library needed. `Measure` blocks for the
conversion while holding the bus, so the reading is atomic against other bus
users.

The driver hard-codes no pins: the wiring is stated in `src/main.adb` and handed
to `Setup`, which records it in the `Device`.

## Build / flash / run

```sh
./x build sht41            # -> app.bin (embedded profile)
./x flash sht41 -p /dev/ttyACM0
./x run   sht41 -p /dev/ttyACM0    # build + flash + serial monitor (115200)
```

If you see `no SHT41 found at 0x44`, check power and the SDA/SCL wiring.

## Notes

- `Measure` takes a `Repeatability` (Low / Medium / **High**, the default) trading
  conversion time for noise.
- `Reset` issues the soft reset; `Status` distinguishes `Bus_Error` (no ACK) from
  `CRC_Error` (data arrived corrupted).
- Uses the controlled I2C `Session`, so like the other Session drivers it targets
  the **embedded / full** profiles, not light-tasking.
