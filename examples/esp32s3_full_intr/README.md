# esp32s3_full_intr — full-profile interrupt-attach test (`ESP32S3_RTS_PROFILE=full`)

The full-profile twin of [`esp32s3_intr_levels`](../esp32s3_intr_levels). It
exists to prove one thing: the portable Ada interrupt layer — `pragma
Attach_Handler` on a protected object, reached through `Ada.Interrupts` — now
builds and runs under the **full** runtime profile.

## Why this is a separate example

The `full` profile sets no `pragma Profile`, so GNAT lowers an interrupt-handler
protected object to the *full dynamic* interrupt machinery
(`System.Interrupts.Register_Interrupt_Handler`, `Static_Interrupt_Protection`,
`Install_Handlers`). The restricted (Ravenscar/Jorvik) `System.Interrupts` that
ships with the embedded profile provides only `Install_Restricted_Handlers`, so
the same source used to fail on full with:

```
construct not allowed in this configuration
System.Interrupts.Register_Interrupt_Handler not defined
```

`crates/esp32s3_rts/full_overlay/gnarl/s-interr.{ads,adb}` is a bare-board
re-implementation of the full `System.Interrupts` surface, layered on the
existing `System.OS_Interface.Attach_Handler` (i.e. `System.BB.Interrupts`) and
the kernel interrupt wrapper. With it in place, `src/blink.adb` — two
library-level interrupt POs that attach with `pragma Attach_Handler` to the L2
and L3 device interrupts — compiles and links on full exactly as on embedded.

Scope today is the **static-attach** path (`pragma Attach_Handler` /
`Install_Handlers`). Run-time `Detach_Handler` at end of scope is limited by
`Configurable_Run_Time` (library-level finalization is not generated).

## What it does

Identical test body to `esp32s3_intr_levels`, so it also re-checks vector
context preservation under the full kernel. A low-priority victim holds four
register-resident FP accumulators (`X := X*Lm*Li`) plus a `THREADPTR` sentinel
across a tight loop, firing the L2 and L3 device interrupts via the `FROM_CPU`
interrupt-matrix sources (no external wiring) while the L5 tick preempts
throughout. The attached handlers count the interrupts.

## Console output (`[intr] <n>`)

Per clean batch:

| Marker | Meaning |
|---|---|
| `1xxxxx` | L2 handler count |
| `2xxxxx` | L3 handler count |
| `3xxxxx` | clean-batch counter |
| `911` | **context lost** — an accumulator or `THREADPTR` came back wrong |

PASS = `1xxxxx`/`2xxxxx`/`3xxxxx` all climbing together with **no** `911`.

## Build / flash

```sh
./x flash full_intr            # from the repo root
```

or, manually:

```sh
bash build.sh
bash flash.sh /dev/ttyACM0
```
