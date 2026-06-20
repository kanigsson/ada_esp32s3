# LEDC — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.LEDC`** LED/PWM controller driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It generates
PWM and measures it back **with no external wiring**.

```
[ledc] bare-metal LEDC PWM self-test (GPIO-sampled, no wiring)
[ledc] duty set=25%    measured=24.6%    freq=5000 Hz  PASS
[ledc] duty set=75%    measured=74.5%    freq=5020 Hz  PASS
[ledc] raii: 8-claimed=y 9th-rejected=y reclaimed=y  PASS
```

## What it checks

Channel 0 is configured for 5 kHz, 10-bit duty on GPIO4 and driven at 25 % and
75 %. The test samples the output pad with `ESP32S3.GPIO.Read` over a 50 ms
window: high samples / total = duty (a clock-independent ratio), rising edges /
elapsed = frequency. Frequency lands on 5 kHz (confirming the 80 MHz APB clock
and the Q10.8 divider + duty-resolution math) and the two duties read back
distinctly — proving real PWM and that `Set_Duty` changes it at run time.

The last line exercises the controlled (RAII) `Channel` handle: claim all eight
channels, confirm a ninth claim is rejected, then — once the handles leave scope,
so `Finalize` stops the output and releases each channel — confirm a fresh claim
succeeds. A `Channel` is non-copyable, so two tasks can't drive or leak one.

## Using the driver

```ada
with ESP32S3.LEDC; use ESP32S3.LEDC;

declare
   Ch : Channel;                          -- limited + controlled (RAII)
begin
   Claim     (Ch, 0);                      -- own channel 0
   Configure (Ch, Freq => 5_000, Pin => 4, Bits => 10);
   Set_Duty  (Ch, Percent => 25.0);        -- any time; you own Ch
end;                                       -- output stopped + channel released
```

Eight channels (`0 .. 7`) fed by four timers; a channel uses timer `Index mod 4`,
so channels whose indices differ by 4 share a frequency — use `0 .. 3` for four
independent ones. Because the `Channel` uses finalization, the driver is
**embedded/full only** (light-tasking forbids `No_Finalization`).

## Build & flash

```sh
./x run esp32s3_ledc_pwm           # build + flash + monitor
# or:
./x build esp32s3_ledc_pwm
./x flash esp32s3_ledc_pwm -p /dev/ttyACM0
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `main/glue.c`.
