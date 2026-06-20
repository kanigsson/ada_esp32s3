# esp32s3_embedded — embedded runtime profile demo

A flashable ESP-IDF example that runs Ada on both ESP32-S3 cores under the bare
GNARL Ada runtime (no FreeRTOS) and exercises the three features the
**`embedded`** runtime profile adds over the default **`light-tasking`** profile:

1. **Tagged dispatching** — a class-wide array of library-level `Shape`s is
   walked with dispatching `Name`/`Area` calls.
2. **Controlled-type finalization** — a `Resource` (a `Limited_Controlled`
   type) is finalized both on scope exit and when a heap object is released
   with `Unchecked_Deallocation`.
3. **Exception propagation** — an exception is raised and caught across a frame,
   and its real `Exception_Name` / `Exception_Message` are printed (needs the
   ZCX unwinder and the exception name table).

Under the default light-tasking profile a raised exception resets the board and
finalization/registration are restricted away; this example deliberately selects
the embedded profile to show them working.

## Build & run

```
./x run embedded      # build + flash + monitor (no ESP-IDF)
```

`main/build_ada.sh` builds the Ada (`app.gpr`) against the pinned runtime crate
with `ESP32S3_RTS_PROFILE=embedded`, then localises the runtime's C heap aliases
so they don't clash with newlib. `sdkconfig.defaults` sets
`CONFIG_COMPILER_CXX_EXCEPTIONS=y`, which is **required** here so the IDF link
keeps `.eh_frame` and registers the DWARF frames the unwinder uses.

Expected console transcript:

```
[C] Ada runtime up on both cores
=== ESP32-S3 embedded profile demo ===
[1] tagged dispatching:
    circle area = 75
    rectangle area = 24
    circle area = 12
[2] controlled finalization:
    [resource initialized]
    (R in scope)
    [resource 1 finalized]
    [resource initialized]
    (P on heap)
    [resource 2 finalized]
[3] exception propagation:
    caught MAIN.MY_ERROR (deliberate)
=== demo complete; environment task now idles ===
```

## Note on local vs library-level types

`Shapes` and `Resources` are declared at **library level** on purpose. The
ESP32-S3 stack lives in DRAM, which is not executable, so a tagged/controlled
type declared *inside a subprogram* — whose dispatch-table thunk GNAT emits as a
trampoline on the stack — faults when dispatched/finalized. Library-level types
put their dispatch tables in flash and work correctly. See the *Runtime
profiles* note in the repository `README.md` for the full root cause and the
`pragma Restrictions (No_Implicit_Dynamic_Code)` build-time guard.
