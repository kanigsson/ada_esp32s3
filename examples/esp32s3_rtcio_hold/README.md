# RTC-IO — bare-metal Ada low-power pad hold (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.RTC_IO`** driver (in `libs/esp32s3_hal`) —
no ESP-IDF, no FreeRTOS, on the Ada runtime. It demonstrates **pad hold** on an
RTC-capable GPIO, **with no wiring**.

```
[rtcio] bare-metal RTC-IO pad-hold self-test (no wiring)
[rtcio] GPIO5: set=1  cleared-while-held=1  cleared-after-release=0  PASS
[rtcio] GPIO6 RTC pull: pull-up reads=1  pull-down reads=0  PASS
```

## What it checks

GPIO5 (one of the RTC-capable pads, GPIO0..21) is driven high and read back. Then
it is **held**: a held pad latches at its current level and ignores ordinary GPIO
writes. The test attempts to `Clear` it — and reads it back **still high** (the
hold latched it). After `Release`, the same `Clear` takes effect and the pad reads
low. So `cleared-while-held=1` (ignored) and `cleared-after-release=0` (obeyed)
prove the hold latch on silicon.

The same latch is what makes hold useful with deep sleep: a held RTC pad keeps
driving its level while the digital core is powered down and across the reset a
wake causes — so you can keep a load enabled or a reset line asserted through
sleep. (This test shows the mechanism while awake, which needs no sleep cycle.)

The second line tests the **RTC-domain pulls**: GPIO6 is routed into the RTC
domain (`Enable_RTC_Input`) and reads back high under an RTC pull-up and low under
an RTC pull-down (`Set_Pull`). These pulls are active in deep sleep, separate from
the digital pulls in `ESP32S3.GPIO`.

## Using the driver

```ada
with ESP32S3.RTC_IO; use ESP32S3.RTC_IO;

ESP32S3.GPIO.Set (5);     -- drive the pad to the wanted level
Hold (5);                 -- latch it (survives GPIO writes, deep sleep, wake reset)
--  ... sleep / do other work ...
Release (5);              -- pad follows the GPIO register again
```

GPIO0..21 are RTC-capable (`RTC_Pin`). RTC-IO is register pokes with no
finalization, so it works under **every** runtime profile.

## Build & flash

```sh
./x run esp32s3_rtcio_hold           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `main/glue.c`.
