# MCPWM — a bare-metal Ada peripheral driver (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.MCPWM`** motor-control-PWM driver (in
`libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime. It generates
edge-aligned PWM on GPIO4 and measures it back **with no external wiring**.

```
[mcpwm] bare-metal MCPWM PWM-output self-test (GPIO-sampled, no wiring)
[mcpwm] duty set=25%   measured=24.6%   freq=20000 Hz  PASS
[mcpwm] duty set=75%   measured=74.6%   freq=20019 Hz  PASS
[mcpwm] pair: A=47.7%   B=48.2%   overlap=0.0%   PASS
[mcpwm] capture: freq=20000 Hz  duty=30.0%   PASS
[mcpwm] fault: run=50%   tripped=0%   resumed=50%   PASS
[mcpwm] carrier: off=100%   on=50%   PASS
[mcpwm] done.
```

## What it checks

A channel (timer + operator) is configured for 20 kHz on GPIO4, then driven at
25 % and 75 % duty. The test measures the result by **sampling the output pad**
with `ESP32S3.GPIO.Read` in a tight loop over a 50 ms window:

- **duty** = high samples / total samples (a clock-independent ratio),
- **frequency** = rising edges / measured elapsed time.

Frequency lands on 20 kHz (confirming the 160 MHz PWM clock and the
prescaler/period math) and the two duties read back distinctly — proving real
PWM generation and that `Set_Duty` changes it at run time. The small duty
under-read (~0.4 %) is sampling-loop bias, well inside tolerance.

The third line is the **complementary + dead-time** test (channel 1): A on one
pad, an inverted B on another, 50 % duty, 1 µs dead-time. Both pads are sampled
at once. A and B each read ~48 % (50 % minus the dead-time gap on each edge) and
the **overlap is 0 %** — the dead-time guarantees A and B are never high
simultaneously, which is the whole point of a half-bridge drive.

The last three lines exercise the remaining submodules:

- **capture** — channel 0's output is fed into capture channel 0 on the *same*
  pad and timestamped on its 80 MHz timer; rising→rising gives the period and
  rising→falling the high time, so freq and duty come out exactly (20000 Hz /
  30.0 %) — more precise than the GPIO sampling above, and it verifies the
  capture submodule itself.
- **fault** — a GPIO we drive is configured as a fault input; channel 0 is set
  to force its output low (one-shot latch) on that fault. The output runs at
  50 %, drops to 0 % the moment the fault is asserted, and resumes at 50 % after
  `Clear_Fault`.
- **carrier** — channel 2 at 100 % duty reads a constant 100 % with the carrier
  off, and ~50 % with it on (the output is chopped at the carrier's own duty) —
  showing the chopper is modulating the output.

## Using the driver

```ada
with ESP32S3.MCPWM; use ESP32S3.MCPWM;

Setup (MCPWM0);                                       -- once per unit

declare
   Ch : Channel;                                      -- limited + controlled (RAII)
begin
   Claim (Ch, MCPWM0, Ch0);                           -- own generator channel 0
   Configure_Channel (Ch, Freq => 20_000, Pin => 4);
   Start (Ch);
   Set_Duty (Ch, Percent => 25.0);                    -- any time; you own Ch
end;                                                  -- Finalize stops + releases it
```

`Setup` is the one-time per-unit clock bring-up. A generator channel is then
`Claim`ed as a **limited, controlled** `Channel` handle: non-copyable (two tasks
can't drive the same channel) and auto-released on scope exit (stopping the
timer). The per-channel ops (`Configure_Channel` / `Start` / `Stop` / `Set_Duty`)
take the handle; `Set_Duty` is a single atomic register write that needs no lock
because you exclusively own the channel. Two units (MCPWM0/1), three channels
each (`Ch0`/`Ch1`/`Ch2`); `Pin` is a validated `ESP32S3.GPIO` pin. For a
half-bridge, add a complementary output with dead-time:

```ada
Configure_Channel (Ch, Freq => 20_000, Pin => 6,
                   Complement_Pin => 7, Dead_Time_Ns => 1_000);
```

This drives `Pin` and an inverted copy on `Complement_Pin`, with the dead-time
inserted on each edge so the two are never high together.

Carrier, fault and capture are also available (carrier/fault/protection act on a
claimed `Channel`; capture is its own claimed `Capture` handle):

```ada
Set_Carrier (Ch, Duty_Eighths => 4);                    -- chop the output

Configure_Fault   (MCPWM0, Fault0, Pin => 8);           -- a fault input (unit-level)
Protect_Channel   (Ch, Fault0, Action => Force_Low);    -- trip Ch safe on it
if Faulted (Ch) then Clear_Fault (Ch); end if;

declare
   Cap : Capture;
begin
   Claim (Cap, MCPWM0, Cap0);                           -- own capture channel 0
   Configure_Capture (Cap, Pin => 10);                  -- measure an input
   if Capture_Pending (Cap) then
      Read_Capture (Cap, Stamp, Falling);               -- 80 MHz timestamp + edge
   end if;
end;
```

## Build & flash

```sh
./x run esp32s3_mcpwm_pwm           # build + flash + monitor
# or:
./x build esp32s3_mcpwm_pwm
./x flash esp32s3_mcpwm_pwm -p /dev/ttyACM0
```

Built as the **embedded** profile (the drivers target it). The report prints
over the USB-Serial-JTAG console via the ROM `esp_rom_printf` glue in
`main/glue.c`.
