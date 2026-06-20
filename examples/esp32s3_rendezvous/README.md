# esp32s3_rendezvous — Ada task rendezvous on the ESP32-S3

Demonstrates the Ada **rendezvous** (synchronous task-to-task message passing —
task entries / `accept` / entry calls) on the bare-metal dual-core ESP32-S3,
running on the **`full`** runtime profile
(`crates/esp32s3_rts/full_overlay`), which carries the complete GNARL
tasking kernel with no Jorvik restrictions. Rendezvous, `select`, and entries
are all forbidden under Ravenscar/Jorvik.

A `Calculator` server task exports three entries — `Add`, `Sub`, `Stop` — and
serves them with a **selective accept** (`select … or accept … end select`),
waiting for whichever entry is called next. The environment task (`Main`'s body)
is the client: it calls each entry and gets the result back through an `out`
parameter. The accept body runs while the caller is suspended in the rendezvous.

```
idf.py set-target esp32s3
idf.py build flash monitor
```

Expected output:

```
[calc] server ready -- waiting for a rendezvous
=== Ada task rendezvous on ESP32-S3 (full tasking) ===
    [calc] Add ( 10, 5 ) => 15
[main] 10 + 5 = 15
    [calc] Sub ( 10, 5 ) => 5
[main] 10 - 5 = 5
    [calc] Add ( 100, 23 ) => 123
[main] 100 + 23 = 123
[calc] stopped -- terminating
[main] done.
```

What this exercises (all impossible under Jorvik): a task **entry** with `in`/
`out` parameters, the **`accept` body** executing with the caller blocked, a
**selective accept** over several entries, and a parameterless rendezvous
(`Stop`) that lets the server task terminate.

## Build / runtime notes

Same bare-metal setup as `esp32s3_full_tasking`: ESP-IDF's app start is
wrapped so core 0 is handed to the GNARL runtime (FreeRTOS never starts), core 1
is taken too, and `main/glue.c` provides the environment-task stack, the Ada
heap, and a `__gnat_task_stack_alloc` hook that places task stacks in external
**PSRAM** (delete the hook + the `CONFIG_SPIRAM*` lines in
`sdkconfig.defaults` to keep them in internal RAM). The Ada side is built into a
relocatable `app_main.o` by `main/build_ada.sh` against the pinned runtime crate
with `ESP32S3_RTS_PROFILE=full`.

## Two former "limitations" — both fixed by disabling W^X

This demo uses the environment task as the client only for simplicity. Two things
that earlier docs called separate limitations are gone, and were in fact the
**same bug**:

1. A **dedicated client task** (two separately declared tasks) was said to
   "corrupt memory during activation/handoff."
2. **Console output from multiple tasks** ("console concurrency") was said to
   fault, forcing all `Put_Line` onto one task.

Both were the **ESP32‑S3 W^X memory-protection feature** refusing to execute the
GCC nested-function **trampoline** a frame-capturing client-task body needs: the
trampoline is written as data (on the DRAM stack, re-pointed to its SRAM1 IRAM
alias `+0x6F_0000` by `gen_runtime.sh`) and then executed, which W^X forbids —
faulting with "Cache disabled but cached memory region accessed." This project
sets **`CONFIG_ESP_SYSTEM_MEMPROT_FEATURE=n`** in `sdkconfig.defaults`; with that,
a dedicated client task **and** concurrent multi-task console output both run
cleanly (A/B-verified on HW). Root cause: `memory/full-profile-acats.md` and
`crates/esp32s3_rts/full_overlay/README.md`.
