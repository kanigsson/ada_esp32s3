# Timer — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.Timer`** general-purpose-timer driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It checks the
timer against the runtime's own clock and exercises its alarm, **no wiring**.

```
[timer] bare-metal general-purpose timer self-test
[timer] 1 MHz count over 50 ms: expected~50000 measured=50015  PASS
[timer] alarm@30000: fired=1 at~30001 us  PASS
```

## What it checks

TIMG0's timer is configured to count at 1 MHz (1 µs per tick). The test resets and
starts it, waits 50 ms of *runtime* time (`Ada.Real_Time`, which is driven by a
different hardware time base), then reads the timer: ~50 000 ticks. The two
independent clocks agreeing confirms the prescaler and 54-bit counter are right.

Then it sets a one-shot alarm at 30 000 ticks, starts from 0, and polls until the
alarm flag fires — measuring ~30 ms elapsed on the runtime clock, confirming the
alarm comparator.

## Using the driver

```ada
with ESP32S3.Timer; use ESP32S3.Timer;

declare
   T : Timer;
begin
   Claim     (T, 0);                      -- TIMG0 (or 1 for TIMG1)
   Configure (T, Tick_Hz => 1_000_000);
   Start     (T);
   N := Value (T);                         -- 54-bit count
   Set_Alarm (T, 30_000);                  -- Alarm_Fired / Clear_Alarm
end;                                       -- stopped + released
```

Two timers (TIMG0 / TIMG1). Because the `Timer` uses finalization, the driver is
**embedded/full only** (light-tasking forbids `No_Finalization`).

## Build & flash

```sh
./x run esp32s3_timer_count           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `glue.c`.
