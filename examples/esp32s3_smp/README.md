# esp32s3_smp_example

A **dual-core SMP** example for the ESP32-S3 bare-metal Ada runtime: a Producer task
pinned to **core 1** posts an incrementing value to a mailbox every 500 ms and
signals; a Consumer task pinned to **core 0** blocks until signalled, then reads
it.  Signalling on core 1 makes the consumer ready on core 0, which the GNARL
kernel delivers as an inter-core poke -- so each value flows core 1 -> core 0:

```
[C] Ada runtime up on both cores
value  1:  producer core 1  -->  consumer core 0
value  2:  producer core 1  -->  consumer core 0
...
```

It consumes the runtime via an Alire **pin** (see `alire.toml`); build, flash
and monitor the whole firmware with `./x run smp` (no ESP-IDF).

## Boot / takeover (main/glue.c)

ESP-IDF brings up the SoC, then `app_main`:
1. pins a carrier task to core 1, which suspends FreeRTOS there and parks;
2. syncs the two cores' CCOUNT (both run at 240 MHz; without this the slave's
   software clock is wrong);
3. suspends FreeRTOS on core 0, **stops the FreeRTOS systimer tick** (the GNARL
   CCOMPARE2 level-5 tick drives `delay until`; leaving the FreeRTOS tick on
   corrupts the slave clock, and `CONFIG_ESP_INT_WDT` is disabled to match);
4. elaborates, calls `__gnat_start_slave_cpus` (releases core 1 into the GNARL
   slave scheduler), and runs the environment task.

The cross-core poke (CPU_INT 31, a FROM_CPU matrix source) and the CCOMPARE2
tick (CPU_INT 16) both reach our `xt_highint5` level-5 vector -- no VECBASE
takeover needed.  This glue is the template a real dual-core app copies.

## Cross-core protected entry

The consumer (core 0) blocks in a real protected-object **entry**
(`entry Get when Full`); the producer (core 1) opens the barrier.  Serving the
entry on core 1 hands the caller back to core 0 through the GNARL served-entry
list plus an inter-core poke (`System.Tasking.Protected_Objects.
Multiprocessors`).  The per-period log line shows the consumer's entry call
completing exactly once between posts -- i.e. it genuinely blocks rather than
busy-returning.

This exercises a runtime fix: `Wakeup_Served_Entry` now unlinks each drained
call before waking it, so the per-CPU served list can never become a cycle.
Without it a single served entry spun the wakeup path hundreds of thousands of
times per second and the caller never blocked.  See
`crates/bb-runtimes/.../gnarl/common/s-tpobmu.adb`.
