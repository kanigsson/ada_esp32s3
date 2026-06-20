# esp32s3_full_tasking — full-Ada-tasking demo (`ESP32S3_RTS_PROFILE=full`)

Runs on the **full** runtime profile (`crates/esp32s3_rts/full_overlay`),
which carries the complete GNARL tasking kernel on the bare-metal ESP32-S3 — no
Jorvik restrictions. Everything is scheduled over the BB kernel
(`s-tassta`/`s-tasren` → the hand-written `s-taprop` → `s-bbthre`).

This example **dynamically allocates** two task objects (`new Worker` — a *task
allocator*, forbidden by Jorvik); the enclosing block is their **master** and
**waits for them to terminate** (task hierarchy + termination) before freeing
their ATCBs. Their stacks are placed in **external PSRAM** (see below).

Other full-tasking constructs verified on this hardware (also forbidden under
Jorvik): **rendezvous** (task entries / `accept` / entry calls with `out`
parameters), **nested tasks** (a task declared in a subprogram, with the
subprogram blocking on return until it terminates), **protected-object entries**
(blocking on a barrier, woken by another task's protected action),
**`Ada.Task_Attributes`** and **`Ada.Dynamic_Priorities`**.

```
./x run full_tasking      # build + flash + monitor (no ESP-IDF)
```

Expected:

```
[C] Ada runtime up on both cores
=== full Ada tasking: dynamic tasks (M4) + abort (M5) ===
    [heartbeat] beat
    [worker 1 ] 1
    [worker 2 ] 1
[main] 2 dynamic tasks allocated; block awaits them
    [worker 1 ] 2 / [worker 2 ] 2 / ... / [worker 1 ] terminating
[main] block exited -> both dynamic tasks terminated + freed
[main] Heartbeat'Terminated before abort = FALSE
[main] Heartbeat'Terminated after  abort = TRUE
[main] done.
```

## Where task stacks and the heap live (internal RAM vs PSRAM)

The full runtime allocates each **task's primary stack** through a weak hook,
`__gnat_task_stack_alloc(size)` (`s-taprop.adb`). Ada `new` allocations use the
**Ada heap** — the `ada_heap` array in `main/glue.c`, bounded by the
`__heap_start`/`__heap_end` defsyms in `main/CMakeLists.txt`. You can place
either, both, or neither in the 8 MB external PSRAM:

| Mode | Task stacks | `new` / heap | How |
|---|---|---|---|
| **Stacks → PSRAM** (default here) | PSRAM | internal | define the hook + enable SPIRAM |
| **Nothing in PSRAM** | internal | internal | delete the hook + SPIRAM lines |
| **Everything in PSRAM** | PSRAM | PSRAM | above + move `ada_heap` to PSRAM |

**1. Task stacks in PSRAM, heap internal (default here).**
`main/glue.c` defines `__gnat_task_stack_alloc` as
`heap_caps_malloc(n, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT)`, and
`sdkconfig.defaults` enables PSRAM (`CONFIG_SPIRAM=y` + `..._MODE_OCT` +
`..._SPEED_80M`). Only task stacks use the 8 MB PSRAM; `new` stays in fast
internal RAM. (The demo prints `stack is in PSRAM`.)

**2. Nothing in PSRAM (all internal).**
Delete the `__gnat_task_stack_alloc` function from `main/glue.c` and remove the
`CONFIG_SPIRAM*` lines from `sdkconfig.defaults`. Task stacks then fall back to
the internal Ada heap; enlarge `ada_heap` (and the `__heap_end` defsym in
`main/CMakeLists.txt`) if you have many or large tasks.

**3. Everything in PSRAM (heap *and* stacks).**
Keep mode 1, and additionally move the Ada heap into PSRAM: mark `ada_heap` in
`main/glue.c` with `EXT_RAM_BSS_ATTR` (enlarge it), and add
`CONFIG_SPIRAM_ALLOW_BSS_SEG_EXTERNAL_MEMORY=y` to `sdkconfig.defaults`. Now all
`new` *and* task stacks live in PSRAM. (You may then delete the hook — task
stacks fall back to the now-PSRAM `ada_heap` — or keep it; either works.)

### The trade-off (any PSRAM mode)

A flash erase/program **disables the SPI cache**, during which PSRAM (and
flash-XIP) is inaccessible — a task running on a PSRAM stack at that moment
would fault (`Cache disabled but cached memory region accessed`). This runtime
**never writes flash at run time**, so it is safe. If you later add flash
writes (NVS/OTA), perform them from an internal-RAM-stacked task with the
PSRAM-stacked tasks suspended (the standard ESP-IDF pattern). The
interrupt/kernel path and the **environment and idle task stacks always stay in
internal RAM** regardless of this setting.

> Abort: **`abort` works** for a task that reaches an abort-completion point
> (the `Heartbeat` `delay` loop above — `'Terminated` goes `False → True`). It
> was enabled by forcing `System.Parameters.No_Abort = False` (the bareboard
> inherited `True` from Ravenscar, which compiled the abort machinery out). Not
> yet: a task parked on a **protected entry** or in a pure **CPU loop**, and
> `select … then abort` (ATC), do not abort yet (they stay put — no crash); the
> remaining kernel pieces are in
> `crates/esp32s3_rts/full_overlay/README.md`. `Ada.Dynamic_Priorities`
> `Set_Priority` works when it keeps the task at or above its ready peers;
> *lowering* the running task below its peers hits a BB-kernel reschedule edge
> case. Terminated tasks are parked and their ATCBs reclaimed only for `new`
> task objects (declared-task ATCBs live in their frame); per-task stacks are
> not yet returned to the heap on termination.
