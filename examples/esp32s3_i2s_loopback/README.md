# I2S — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.I2S`** digital-audio driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It streams PCM
samples out and back over DMA and verifies them **with no external wiring**.

```
[i2s] bare-metal I2S full-duplex DMA loopback self-test (no wiring)
[i2s] full-duplex loopback (64 samples): PASS
[i2s] done.
```

## What it checks

I2S0 is brought up as a stereo 16-bit master. The S3 I2S has no CPU FIFO — data
moves only through the GDMA crossbar — so this exercises the whole DMA path: a
64-word (128-byte) buffer is shifted out on the data-out line and simultaneously
captured on the data-in line by a single full-duplex `Transfer`, then compared
word for word.

The loopback needs **no wiring**: the hardware `SIG_LOOPBACK` bit makes the
transmitter and receiver share WS + BCK internally, and the data-out signal is
fed back into data-in on one GPIO pad through the matrix (the same single-pad
trick `ESP32S3.SPI` uses). So the test proves real serial framing and round-trip
DMA on silicon, not just a register echo.

It also exercises the controlled (RAII) `Session`: `Acquire` on scope entry,
automatic `Release` (the port's guard handed back) when the handle leaves scope.

## Using the driver

```ada
with ESP32S3.I2S; use ESP32S3.I2S;

Setup (I2S0, Sample_Rate => 16_000, Bits => Bits_16);     -- once, stereo master
Configure_Pins (I2S0, Bclk => 5, Ws => 6, Dout => 7, Din => 8);
--  or, for this wiring-free self-test:  Enable_Loopback (I2S0, Pad => 4);

declare
   S : Session;                       -- limited: cannot be copied/shared
begin
   Acquire  (S, I2S0);                -- suspends until the port is free
   Transfer (S, Tx'Address, Rx'Address, Len);   -- full-duplex DMA
   --  or Write (S, Tx'Address, Len) to a DAC / Read (S, Rx'Address, Len) from a mic
end;                                  -- auto-released on scope exit
```

Two ports (I2S0 / I2S1), each a stereo Philips/TDM master on its own GDMA
channel. Because the `Session` uses finalization, the driver is **embedded/full
only** (light-tasking forbids `No_Finalization`).

## Build & flash

```sh
./x run esp32s3_i2s_loopback           # build + flash + monitor
# or:
./x build esp32s3_i2s_loopback
./x flash esp32s3_i2s_loopback -p /dev/ttyACM0
```

Built as the **embedded** profile (the drivers target it). The report prints
over the USB-Serial-JTAG console via the ROM `esp_rom_printf` glue in
`main/glue.c`.
