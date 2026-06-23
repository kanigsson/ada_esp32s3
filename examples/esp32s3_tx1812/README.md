# TX1812 addressable RGB LED over RMT — bare-metal Ada (ESP32-S3)

Drives a single **TX1812** addressable RGB LED (WS2812 / "NeoPixel"-compatible
single-wire protocol) on **IO48** using the **RMT** peripheral. It cycles the LED
**red → green → blue → white → off** (~0.6 s each) and prints each colour, so you
can match the serial log to what you see.

```
[led] TX1812 addressable RGB LED on IO48, driven by RMT
[led] acquire RMT TX channel: OK
[led] red
[led] green
[led] blue
[led] white
[led] off
...
```

## The driver — `ESP32S3.TX1812`

A `Strip` is a **claimed handle**: `Acquire` it (which takes an RMT transmit
channel and routes it to the data pin), `Set` pixel colours into its buffer, then
`Show` to clock them out. The RMT channel is **released automatically** when the
`Strip` leaves scope (its channel component is controlled), so you acquire the
resource before driving the LED and never leak it.

```ada
S : ESP32S3.TX1812.Strip (Count => 1);
...
ESP32S3.TX1812.Acquire (S, Pin => 48, Channel => 0);
ESP32S3.TX1812.Set     (S, Index => 1, C => (R => 48, G => 0, B => 0));
ESP32S3.TX1812.Show    (S);
```

Each data bit becomes one RMT symbol (a '1' is long-high/short-low, a '0' the
reverse, ~1.2 µs/bit; the channel idles low afterwards, providing the >80 µs
reset latch). Wire order is **GRB**; per-bit timings are named constants in
`esp32s3-tx1812.adb`, within WS2812/TX1812 tolerance — tune there if a part is
fussy.

## Wiring

| Signal | Pin |
|---|---|
| TX1812 data in | **IO48** |

On many ESP32-S3 boards IO48 is the **on-board RGB LED**. For an external LED,
wire its DIN to IO48 (and share ground / 5 V or 3.3 V per the part).

## Single LED for now

The HAL `RMT.Transmit` sends at most 47 symbols per burst and each LED needs 24,
so this drives **one** LED (`Count => 1`). The API is already shaped for a string
(`Count`, per-pixel `Set`); driving a longer chain needs RMT wrap/refill support
(a later step) — only `Show`'s transport changes.

## Build / flash / run

```sh
./x build tx1812
./x flash tx1812 -p /dev/ttyACM0
./x run   tx1812 -p /dev/ttyACM0
```
