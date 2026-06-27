# I2S PDM — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Demo for the **PDM mode** of the reusable **`ESP32S3.I2S`** driver (in
`libs/esp32s3_hal`) — the hardware **PCM↔PDM** sigma-delta converters, no
ESP-IDF, no FreeRTOS, on the Ada runtime. This example captures a **PDM
microphone** (the receive `PDM2PCM` path).

```
[i2s-pdm] bare-metal I2S PDM microphone capture demo (needs an external PDM mic)
[i2s-pdm] wire a PDM mic: CLK <- GPIO5   DATA -> GPIO6   (plus VDD/GND)
[i2s-pdm] block 1: min=-1840 max=2010 peak-to-peak=3850 <-- signal present
...
[i2s-pdm] capture done.
```

## What PDM is, and why it's useful

PDM (pulse-density modulation) is the sigma-delta sibling of PWM: a 1-bit
oversampled stream whose *density* of ones encodes the analog level. The S3 I2S
has the conversion in hardware in **both directions**, and the driver exposes
both via `Mode => PDM` at `Setup`:

- **RX `PDM2PCM`** decimates a 1-bit PDM input back to PCM. PDM is the format
  *emitted* by digital **PDM microphones** and some PDM-output **ADCs**; the
  converter turns their bitstream into PCM samples. The ESP is the clock master:
  it drives the device clock out and reads the bitstream in.
- **TX `PCM2PDM`** turns each PCM sample into a 1-bit stream — drive it into a
  class-D amplifier or an RC low-pass for analog audio out (the S3 has no analog
  DAC, so this is the way to get one).

The DMA moves ordinary PCM in both cases, so `Write` / `Read` / `Transfer` are
unchanged; only the on-wire format differs.

## ⚠ This demo needs external hardware

Unlike the standard-I2S loopback and the other HAL self-tests, **PDM cannot be
self-tested on-chip** (both verified on silicon):

- There is **no internal loopback** for the converters — `SIG_LOOPBACK` only
  shares the *standard-I2S* WS+BCK, not the bit timing between `PCM2PDM` and
  `PDM2PCM`, so an internal `PCM→PDM→PCM` loop does not recover the signal.
- A **static level won't substitute for a mic** — driving the data pin from a
  GPIO (a pull resistor, or a strong output) only nudges the decimator, because
  the converter's mandatory high-pass filter strips DC: a constant 1 or 0 is pure
  DC and gets rejected.

Genuine verification needs a real PDM device producing a toggling bitstream. Wire
a PDM microphone:

| Mic pin | ESP32-S3 |
|---|---|
| `CLK`  | GPIO 5 (the ESP **drives** this) |
| `DATA` | GPIO 6 |
| `SEL`/`L-R` | GND or VDD per the mic datasheet (selects the channel/edge) |
| `VDD` / `GND` | 3V3 / GND |

The demo captures eight ~256-frame blocks and prints each block's peak-to-peak
level, so you can watch the level rise when you speak into or tap the mic. With
no mic attached the data line floats — expect silence or noise.

## Using the driver

```ada
with ESP32S3.I2S; use ESP32S3.I2S;

Setup (I2S0, Sample_Rate => 16_000, Bits => Bits_16, Mode => PDM);   -- PDM mode

--  PDM microphone (RX): clock out on Ws, data in on Din.
Configure_Pins (I2S0, Bclk => No_Pin, Ws => 5, Dout => No_Pin, Din => 6);
--  PDM out (TX) to a class-D / RC: route Ws (PDM clock) + Dout instead.

declare
   S : Session;                       -- limited: cannot be copied/shared
begin
   Acquire (S, I2S0);
   Read    (S, Rx'Address, Len);      -- PDM mic -> PCM
   --  or Write (S, Tx'Address, Len)  -- PCM -> PDM out (to a class-D amp)
end;                                  -- auto-released on scope exit
```

Because the `Session` uses finalization, the driver is **embedded/full only**
(light-tasking forbids `No_Finalization`).

## Build & flash

```sh
./x run esp32s3_i2s_pdm                 # build + flash + monitor
# or:
./x build esp32s3_i2s_pdm
./x flash esp32s3_i2s_pdm -p /dev/ttyACM0
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `glue.c`.
