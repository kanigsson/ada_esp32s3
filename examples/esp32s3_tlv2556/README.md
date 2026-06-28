# TLV2556 — a bare-metal Ada SPI ADC driver (ESP32-S3, no FreeRTOS)

Bring-up for the reusable **`ESP32S3.TLV2556`** driver (in `libs/esp32s3_hal`) —
a TI **TLV2556**, a 12-bit, 11-channel, 200-kSPS serial ADC with an internal
reference. No ESP-IDF, no FreeRTOS, on the Ada runtime.

```
[tlv2556] TI TLV2556 12-bit ADC bring-up (SPI2, CS=IO12)
[tlv2556] self-test: zero=0 half=2047 full=4095   PASS
[tlv2556] AIN0 = 195 / 4095
[tlv2556] done.
```

## What it checks

1. **Initialize** — programs configuration register 2 (reference, pin-19 = EOC,
   normal mode).
2. **Self-test** — reads the chip's three internal test voltages. They are
   *ratiometric to the reference rails*, so they read fixed codes —
   `Test_Zero → 0`, `Test_Half → 2048`, `Test_Full → 4095` — **regardless of the
   reference voltage or any analog wiring**. That makes them a complete
   end-to-end check of the SPI protocol with nothing connected to the inputs
   (the ADC equivalent of reading a flash JEDEC id).
3. **AIN0** — reads analog input 0 and reports its raw 12-bit code.

## The protocol, briefly

The TLV2556 is **SPI mode 0** and **pipelined**: each 16-clock I/O cycle clocks
an 8-bit command in on DATA IN — the top 4 bits select the input (or a command),
the low 4 are configuration register 1 — while the *previous* conversion's 12-bit
result clocks out on DATA OUT, MSB first (16-bit frame, 4 LSB pad zeros). So a
sample is read on the cycle *after* its channel is addressed; `Read` hides that
by priming the conversion, waiting out the ~5.5 µs conversion time, then reading
it back. The driver uses uniform 16-clock (2-byte) transfers throughout.

## Sharing the bus — the per-device chip select

Like the W25Q flash, the ADC's chip select is its **own GPIO (IO12)**: name it as
`Dev := (Host => SPI2, CS_Pin => 12, others => <>)` and the SPI driver drives that
GPIO active-low, held across each conversion, suppressing the host's hardware
`CS0` for the session — so the ADC coexists with the flash and any other device on
SPI2. (A select that is not one plain GPIO would supply a `CS_CB` callback
instead.)

## Hardware

| Signal | Pin | Notes |
|---|---|---|
| SCLK (I/O CLOCK) | GPIO1 | shared SPI2 bus |
| DATA IN ← MOSI | GPIO4 | shared SPI2 bus |
| DATA OUT → MISO | GPIO45 | shared SPI2 bus |
| CS | GPIO12 | ADC-only, active-low, software-driven |

3V3 / GND. The reference defaults to **external** (the chip's power-on default);
set `Ref => Internal_4096mV` at `Initialize` to use the on-chip 4.096-V reference
(then 1 LSB = 1 mV). The self-test passes either way.

## Build & run

```
./x run esp32s3_tlv2556       # build + flash + report over USB-Serial-JTAG
```
