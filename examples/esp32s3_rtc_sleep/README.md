# RTC — bare-metal Ada low-power (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.RTC`** low-power driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It shows
retained memory surviving deep sleep with a timer wake, **no wiring**.

```
rst:0x1 (POWERON) ...
[rtc] boot: wake=power-on          retained boot-count=1
[rtc] entering deep sleep for ~2000 ms (console drops until wake)...
rst:0x5 (DSLEEP) ...
[rtc] boot: wake=deep-sleep-timer  retained boot-count=2
...
rst:0x5 (DSLEEP) ...
[rtc] boot: wake=deep-sleep-timer  retained boot-count=4
[rtc] FINAL: boot-count=4 last-wake=deep-sleep-timer  PASS
```

## What it checks

A boot counter lives in **retained RTC slow memory** (8 KB at `0x5000_0000`),
which keeps its contents while the chip is in deep sleep. Each boot the program:

1. reads `Last_Wake` — was this a power-on or a deep-sleep wake?
2. bumps the counter (a deep-sleep wake continues it; anything else starts at 1);
3. for the first few boots, enters **deep sleep with a ~2 s timer wake**.

Across the cycles the counter persists and increments (`1 → 2 → 3 → 4`) and the
wake cause turns into `deep-sleep-timer` — and the ROM's own reset line reads
`rst:0x5 (DSLEEP)` — proving the digital core really powered down and woke on the
RTC timer with RTC memory intact. After four boots the board stays awake and
repeats the final state so it can be captured cleanly (the USB-JTAG console drops
during each sleep).

`Disable_Super_Watchdog` is called first: a deep-sleep wake can leave the RTC
super-watchdog armed, which would otherwise reset a woken app that stays awake.

## Using the driver

```ada
with ESP32S3.RTC; use ESP32S3.RTC;

Boot_Count : Interfaces.Unsigned_32
  with Import, Volatile, Address => ESP32S3.RTC.Slow_Memory;

case Last_Wake is
   when Deep_Sleep_Timer | Deep_Sleep_GPIO => Boot_Count := Boot_Count + 1;
   when others                             => Boot_Count := 1;
end case;

Deep_Sleep_For (2.0);                              -- timer wake; does not return
--  or Deep_Sleep_Until (Pin => 0, High => True);  -- RTC-GPIO (EXT1) wake
```

RTC is register pokes with no finalization, so it works under **every** runtime
profile (light-tasking included).

## Build & flash

```sh
./x run esp32s3_rtc_sleep           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `glue.c`. (The console
disconnects and re-enumerates on each deep-sleep cycle — expected.)
