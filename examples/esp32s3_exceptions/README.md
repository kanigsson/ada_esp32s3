# Exceptions — local, propagated, re-raised, unhandled (ESP32-S3, no FreeRTOS)

A teaching demo of what happens to an Ada exception on the bare-metal ESP32-S3,
on the **embedded** runtime profile — no ESP-IDF, no FreeRTOS. It shows all four
outcomes in order, ending with an unhandled exception reaching the
**last-chance handler**.

```
=== ESP32-S3 exception demo (embedded profile) ===
[1] local handling:
    caught locally: CONSTRAINT_ERROR
[2] propagation across a call:
    caught from Inner: MAIN.SENSOR_FAULT (inner detected a fault)
[3] re-raise to an outer handler:
    inner handler: cleaning up, then re-raising
    outer handler caught the re-raised MAIN.SENSOR_FAULT
[4] unhandled exception -> last-chance handler:
    raising with NO handler; the last-chance handler runs next...
*** LAST CHANCE HANDLER: unhandled MAIN.SENSOR_FAULT -- nobody is going to catch this ***
```

## What it shows

| Step | Behaviour |
|---|---|
| **[1] local** | A predefined `Constraint_Error` (a failed `Positive` range check) raised and caught in the *same* block. |
| **[2] propagation** | A nested `Inner` raises a user-defined `Sensor_Fault`; the **caller** catches it — propagation across a call, which needs the embedded/full ZCX unwinder. |
| **[3] re-raise** | An inner handler does local cleanup, then a bare `raise;` hands the *same* exception to an outer handler. |
| **[4] unhandled** | Nobody catches it, so it reaches the **last-chance handler** — the routine the runtime calls for any exception that escapes the whole program. |

## The last-chance handler

The runtime's default last-chance handler reports the exception through
`System.IO` and then **resets** the chip. On this bare boot two things make that
awkward for a demo: `System.IO` is not wired to the console (so its report would
be invisible), and a reset would loop the demo forever. So this example installs
its **own** handler (`src/last_chance.adb`): the embedded runtime calls the
last-chance handler through the C symbol `__gnat_last_chance_handler`, so exporting
our own under that name means the runtime's version is never linked. Ours prints
the exception over the ROM console and **halts** instead of resetting — which is
why step [4] is both visible and final (no reset loop). A real product would
typically log and reset (or enter a safe state); see the Debugging chapter.

## Why the embedded profile

The `light-tasking` profile is `No_Exception_Propagation`: a raise that is not
handled in the *same* subprogram cannot propagate, so steps [2] and [3] are
impossible there — every raise would go straight to the last-chance handler.
`embedded` (and `full`) add zero-cost (ZCX) exception propagation, so catching
across calls, re-raising, and reading the exception name/message all work. See the
*Embedded Ada* chapter's exceptions section for the full per-profile comparison.

> The demo body prints with `Ada.Text_IO` (the runtime routes it to the
> USB-serial console). The last-chance handler uses the ROM `esp_rom_printf`
> directly (via `main/glue.c`), because it runs in the fragile state just after
> an exception has escaped everything.

## Build & flash

```sh
./x run esp32s3_exceptions             # build + flash + monitor
# or:
./x build esp32s3_exceptions
./x flash esp32s3_exceptions -p /dev/ttyACM0
```

Built as the **embedded** profile.
