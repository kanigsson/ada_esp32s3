# TX1812 addressable RGB LED string over RMT — bare-metal Ada (ESP32-S3)

Drives a string of **TX1812** addressable RGB LEDs (WS2812 / "NeoPixel"-compatible
single-wire protocol) on **IO48** using the **RMT** peripheral. The example
declares a **64-LED** string, then cycles the whole string **red → green → blue →
white → off** (~0.6 s each), printing each colour.

```
[led] TX1812 string of 64 LEDs on IO48 via RMT (wrap-streamed; on-board LED = pixel 1)
[led] acquire RMT TX channel: OK
[led] red
[led] green
[led] blue
[led] white
[led] off
...
```

With **no physical string attached**, the board's on-board LED on IO48 is just
**pixel 1** of the chain, so it cycles colours — confirming the stream transmits.
Wire a real string into IO48 and all 64 light up.

## The driver — `ESP32S3.TX1812`

A `Strip (Count)` is a **claimed handle**: `Acquire` it (takes an RMT transmit
channel + routes it to the pin), `Set`/`Set_All` pixel colours into its buffer,
then `Show` to clock them out. The RMT channel is **released automatically** when
the `Strip` leaves scope.

```ada
ESP32S3.TX1812.Acquire (Panel, Pin => 48, Channel => 0);
ESP32S3.TX1812.Set_All (Panel, (R => 48, G => 0, B => 0));   --  all red
ESP32S3.TX1812.Show    (Panel);
```

Wire order is **GRB**; per-bit timings are named constants in
`esp32s3-tx1812.adb`, within WS2812/TX1812 tolerance.

## Static, pre-elaborated memory (`LED_Panel`)

A `Strip` is **statically sized by its `Count` discriminant** — it carries both
the `Count` pixel colours and the `Count×24` RMT-symbol frame buffer. The example
declares the string **at library level** in `LED_Panel`, so its **~6.4 KiB**
(64 colours + 1536 symbols) is reserved **in `.bss` at elaboration** — no heap,
and the **link fails if it doesn't fit**. So "do we have enough memory for 64
LEDs?" is answered by the build (check `led_panel__panel` in `app.map`).

## How the frame reaches the LEDs — two RMT transports

The RMT symbol RAM is only **48 symbols/block**, and each LED is 24 symbols, so
the HAL `RMT` driver streams the frame two ways (`Show`/`RMT.Transmit` pick
automatically):

- **Phase 1 — multi-block (one shot):** `Acquire (..., Blocks => 1 .. 4)` gives
  the channel up to 4 RAM blocks, so up to ~7 LEDs go out in a single load (no
  re-fill). It borrows the higher TX channels' RAM.
- **Phase 2 — wrap streaming (any length):** for a burst bigger than the RAM, the
  channel runs in wrap mode and the driver **re-fills the symbol RAM in 24-symbol
  halves** as it drains (polled in the blocking `Transmit` loop — no ISR). This
  is how the 64-LED frame goes out through 48 symbols of RAM.

> The blocking `Transmit` busy-polls the re-fill, so keep higher-priority
> interrupts short. A future async/DMA path would lift that.

## Wiring

| Signal | Pin |
|---|---|
| TX1812 data in (string DIN) | **IO48** |

On many ESP32-S3 boards IO48 is the **on-board RGB LED** (= pixel 1). A real
string needs an adequate 5 V supply and often 3.3 V→5 V level shifting on DIN.

## Build / flash / run

```sh
./x build tx1812
./x flash tx1812 -p /dev/ttyACM0
./x run   tx1812 -p /dev/ttyACM0
```
