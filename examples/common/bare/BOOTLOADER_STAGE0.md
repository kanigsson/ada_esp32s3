# Stage 0 — minimal IDF-free 2nd-stage bootloader: design

**Goal.** Replace the vendored 21 KB `bootloader.bin` (the last vendored *binary*) with our
own minimal 2nd-stage bootloader. The 1st-stage **mask ROM** still loads it from flash `0x0`
(silicon — not removable). Endgame: a pure stack (ZFP-Ada bootloader → Jorvik app) and — the
real motivator — **owning the flash/MSPI bring-up so PSRAM works** (a RAM-resident bootloader
has no flash-XIP rug to pull out from under itself, which is exactly what crashed the app-side
PSRAM init).

Extracted from ESP-IDF **v5.4.4** (`~/esp/esp-idf`), the source the vendored blob was built from.

---

## What the IDF 2nd-stage actually does

### A. `bootloader_init()` — bring-up  (`bootloader_support/src/esp32s3/bootloader_esp32s3.c`)
| step | what | for us |
|---|---|---|
| analog reset cfg + super-WDT feed | register pokes | we already disable WDTs (`stubs.c`) |
| `bootloader_init_mem` + clear `.bss` | our own bss | trivial |
| **`bootloader_clock_configure`** | PLL/clock | ROM `rtc_clk_*`; we already do the 240 MHz switch |
| console + banner | UART | DROP / minimal |
| `cache_hal_init` + `mmu_hal_init` | cache+MMU regs | we already touch these |
| `bootloader_flash_update_id` / `xmc_startup` | flash ID | ROM `esp_rom_spiflash_*` |
| read+check the bootloader's own header | — | DROP (that's us) |
| **`bootloader_init_spi_flash`** | **flash clock / mode / dummy** | **the PSRAM-relevant flash-timing setup** |
| WDT reset check | — | DROP / minimal |

### B. `bootloader_utility_load_boot_image()` — load + jump  (`bootloader_utility.c`)
1. read **partition table** (flash `@0x8000`, magic `0x50AA`, 32-byte `esp_partition_info_t` entries) → find `type=app / subtype=factory`.
2. read **app image header** (magic `0xE9` → `segment_count`, `entry_addr`).
3. for each of N segments (each header = `load_addr`, `data_len`, then the data):
   - `should_load(load_addr)` → it's **IRAM/DRAM** → **copy flash → SRAM** (`memcpy`).
   - `should_map(load_addr)`  → it's **IROM `0x42…` / DROM `0x3C…`** → record `(flash_paddr, vaddr, size)`.
4. `set_cache_and_start_app()`:
   - `Cache_Read_Disable(0)` + `Cache_Flush(0)` + disable ext-mem cache  *(ROM)*
   - set MMU page size = 64 KB + `mmu_hal_unmap_all`                      *(ROM)*
   - DROM: `Cache_Dbus_MMU_Set(vaddr, paddr, 64, pages)` for MMU 0 and 1  *(ROM — **we already call this for PSRAM**)*
   - IROM: `Cache_Ibus_MMU_Set(...)` for MMU 0 and 1                       *(ROM)*
   - re-enable cache; **jump to `entry_addr`**.

---

## Minimal subset — KEEP
**Init:** WDT off · clock (PLL) · flash init (clock/mode/dummy) · cache+MMU init.
**Load:** partition-table read → app-image read → segment load (copy RAM, map flash IROM/DROM) → enable cache → jump.

## DROP — none of it applies
OTA slot selection · secure boot / signature · flash encryption · anti-rollback · deep-sleep
wake-stub resume · eFuse virtual mode · multi-image/recovery paths · banner/console (optional
debug only). Image checksum/hash: keep a cheap checksum, or skip for dev.

## ROM does the silicon (135 primitives exposed; we already call ~a dozen via `rom_syms.ld`)
- flash: `esp_rom_spiflash_read`, `esp_rom_spiflash_config_*`, `bootloader_flash_*`
- cache/MMU: `Cache_Read_Disable/Flush/Enable`, **`Cache_Ibus_MMU_Set` = 0x400019a4**, **`Cache_Dbus_MMU_Set` = 0x400019b0**, `Cache_Set_IDROM_MMU_Size`
- clock: the `rtc_clk_*` we already drive for 240 MHz
→ We **orchestrate ROM functions**; we do not write flash/cache drivers.

## The new logic we actually write (~300–400 lines)
- partition-table parse (read `0x8000`, walk 32-byte entries, match app/factory)
- image-header + segment-header parse (two small packed structs)
- the segment loop (classify by address range → `memcpy` or record-for-map)
- the orchestration + the final map + cache-enable + jump

## PSRAM — the payoff
Add an `init_psram()` step **after `bootloader_init_spi_flash`** (MSPI is up) and **before the
jump**. It runs from RAM, so the MSPI/flash-timing reconfig that crashed the app-side init is
now safe (no XIP coherency rug). Either bring up PSRAM outright here, or just leave the MSPI
timing in the state the app's PSRAM init expects. **The whole psram wall dissolves.**

## ZFP-Ada shape
- Runtime: **Zero-Footprint** (or `light` minus tasking). The bootloader runs *before* GNARL —
  no tasking / exceptions / secondary stack / heavy elaboration. `pragma Restrictions
  (No_Exception_Propagation, No_Elaboration_Code, No_Secondary_Stack, …)`.
- Its own `.gpr`, built to a RAM-resident image (esptool, image magic `0xE9`, loaded by the ROM
  at flash `0x0`).
- ROM functions via `pragma Import (C, …)` + their addresses in a `PROVIDE` linker list (like
  our `rom_syms.ld`).
- Image-header / partition structs as Ada records with representation clauses.
- Stays asm (tiny): `_start` — set SP/VECBASE, clear bss, call the Ada entry. Everything else is
  Ada calling ROM.
- This is **Ada-as-portable-assembler**, *not* "Ada using our RTS" — two separate stages that
  share a toolchain + the SoC knowledge we've already built.

## Stage 1 plan (de-risk; do not big-bang)
1. **C first** — a minimal loader that boots ONE fixed app (factory partition) and jumps.
   Prove it replaces the blob and boots `gpio0_blink`. (De-risks cache/MMU/flash without the
   Ada-runtime variable in play.)
2. **PSRAM** — add `init_psram()` before the jump → `esp32s3_psram` finally works.
3. **Ada-ify** — port the validated C loader to ZFP-Ada.

## Risks
- Flash/cache/MMU bring-up is unforgiving: a bug = **silent no-boot** (JTAG-halt to debug, as we
  learned on PSRAM).
- The flash timing (`bootloader_init_spi_flash`) must match the chip — easiest to mirror the
  IDF's exact sequence first, then trim.
- We still depend on the 1st-stage ROM (it loads us from flash `0x0`) — not removable.

## Verdict
Bounded and tractable: ~300–400 lines of new logic + ROM orchestration, and we've already
written half of it (cache bring-up, 240 MHz switch, code relocation, core-1 cold start) in the
current bare boot. The flash/cache/MMU bring-up is the genuinely-hard part, but the ROM provides
the primitives. **Recommended start: the C-first minimal loader (Stage 1.1).**
