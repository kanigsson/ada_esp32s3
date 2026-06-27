# LCD (i80 parallel) — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.LCD`** driver (in `libs/esp32s3_hal`), the
LCD half of the LCD_CAM controller — no ESP-IDF, no FreeRTOS, on the Ada runtime.
It DMA-streams a buffer out an 8-bit Intel-8080 parallel bus and verifies the
pixel clock **with no external wiring**.

```
[lcd] bare-metal LCD i80 8-bit parallel DMA-TX self-test (no wiring)
[lcd] dma transmit (4000 bytes): trans-done=1  PASS
[lcd] pclk: set=200 kHz measured=200 kHz  PASS
```

## What it checks

The LCD is configured for an 8-bit "i80" bus at a 200 kHz pixel clock, data lines
on GPIO 4..11 and PCLK on GPIO 13. A 4000-byte buffer is streamed out over the
GDMA crossbar — one byte per pixel clock — and the controller's transfer-done
interrupt confirms the whole DMA → LCD data path completed. Because exactly one
byte is clocked per PCLK, timing the transfer against the runtime clock recovers
the pixel-clock rate: 4000 bytes in ~20 ms ⇒ 200 kHz, matching what was set. So
the test verifies both the DMA data path and the pixel-clock divider on silicon.

## Using the driver

```ada
with ESP32S3.LCD; use ESP32S3.LCD;

Setup (Pclk_Hz => 1_000_000);                          -- once; claims a GDMA channel
Configure_Pins (Data => (4, 5, 6, 7, 8, 9, 10, 11), Pclk => 13);

declare
   S : Session;  Ok : Boolean;
begin
   Acquire  (S);
   Transmit (S, Buf'Address, Buf'Length, Ok);          -- one byte per pixel clock
end;                                                   -- controller released
```

The `Session` is the same limited, controlled handle as SPI. Because it uses
finalization, the driver is **embedded/full only** (light-tasking forbids
`No_Finalization`). This covers the 8-bit transmit path; the camera-receive half
and the 16-bit / RGB modes of LCD_CAM are future work.

## Build & flash

```sh
./x run esp32s3_lcd_i8080           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `glue.c`.
