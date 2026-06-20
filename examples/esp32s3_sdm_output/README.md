# SDM — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.SDM`** sigma-delta-modulator driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It generates a
density-modulated output and measures it back **with no external wiring**.

```
[sdm] bare-metal SDM sigma-delta density self-test (GPIO-sampled, no wiring)
[sdm] density set=25%    measured=25.0%    PASS
[sdm] density set=50%    measured=50.0%    PASS
[sdm] density set=75%    measured=75.0%    PASS
[sdm] raii: 8-claimed=y 9th-rejected=y reclaimed=y  PASS
```

## What it checks

Channel 0 is routed to GPIO4 and set to 25 %, 50 % and 75 % density. A sigma-delta
stream's average level equals its programmed density, so the test samples the
output pad with `ESP32S3.GPIO.Read` over a 50 ms window (high samples / total) and
each reads back its set density. Normally you'd put an RC low-pass on the pin to
get the analog voltage; here we just average it digitally.

A low carrier frequency (`Carrier_Hz => 400_000`) is used so the pulse stream is
slow enough for the GPIO sampler to oversample each bit and average fairly — a
fast 50 %-density square would otherwise alias against the fixed sampling loop.
(The density itself is carrier-independent.)

The last line exercises the controlled (RAII) `Channel` handle: claim all eight,
confirm a ninth is rejected, then reclaim once the handles leave scope.

## Using the driver

```ada
with ESP32S3.SDM; use ESP32S3.SDM;

declare
   Ch : Channel;
begin
   Claim       (Ch, 0);
   Configure   (Ch, Pin => 4);            -- route to GPIO4
   Set_Density (Ch, Percent => 25.0);
end;                                       -- output low + released
```

Eight channels (`0 .. 7`). Because the `Channel` uses finalization, the driver is
**embedded/full only** (light-tasking forbids `No_Finalization`).

## Build & flash

```sh
./x run esp32s3_sdm_output           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `main/glue.c`.
