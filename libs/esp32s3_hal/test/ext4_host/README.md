# ext4 host test harness (native x86)

Runs the **pure-Ada ext4 filesystem** (`ESP32S3.Ext4.*`, from
`libs/esp32s3_hal/src/ext4`) on the development host against a **file-backed
block device**, then cross-checks the result with the host kernel's own
`e2fsck`. No hardware, no flashing — a fast loop for filesystem-logic bugs.

The harness builds the *same* FS sources the firmware uses (the `.gpr`
`Source_Files` whitelist pulls in every portable unit and omits only the
on-target block-device adapters `*-sdmmc_source` / `*-sd_spi_source`), so a bug
reproduced here is a real FS bug — and a bug that *only* shows on target points
at the SDMMC/SD-SPI layer instead.

## Block device

`ext4_host.adb` plugs an `Ada.Direct_IO` view of an image file into the
`ESP32S3.Block_Dev` seam (512-byte sectors) — the same abstraction the on-target
`SDMMC_Source` adapter implements. Every write persists exactly, so the image is
a "perfect" device: any divergence from `e2fsck` is the filesystem's doing.

## Run

```sh
./run.sh
```

It auto-discovers an Alire native GNAT + gprbuild, builds, then for each
scenario formats a fresh `mkfs.ext4 -O ^metadata_csum` image, runs the scenario,
and reports `e2fsck -fn`:

```
  one            e2fsck CLEAN
  two            e2fsck CLEAN
  rerun          e2fsck CLEAN
  battery        e2fsck CLEAN
  dirty_battery  e2fsck CLEAN
```

Requirements: a native GNAT toolchain (Alire `gnat_native` + `gprbuild` are
found automatically) and `e2fsprogs` (`mkfs.ext4`, `e2fsck`).

## Scenarios

| Scenario | What it does |
|---|---|
| `one` | create a file + `mkdir`, **single** commit |
| `two` | create + commit, then `mkdir` + commit (two transactions) |
| `rerun` | session A writes a file; session B re-opens, unlinks it + commits, then `mkdir` + commits |
| `battery` | the full `esp32s3_ext4_write` op set incl. a 1 MiB file, one commit |
| `dirty_battery` | a prior single-file session, **then** the full battery on that dirty image (exact mirror of the on-device re-run) |

The `rerun` / `dirty_battery` scenarios were added while chasing a free-count
drift seen on a *re-run, already-written SD card*. All scenarios are
`e2fsck`-clean here against a perfect block device, which localised that drift
to the on-device SDMMC write/read path rather than the filesystem.

## Add a scenario

Extend the `if Scenario = ...` chain in `ext4_host.adb` (each branch drives the
`ESP32S3.Ext4.FS` API: `Create_File`/`Write_File`/`Mkdir`/`Link`/`Symlink`/
`Rename`/`Unlink`/`Commit`/`Close`) and add its name to the loop in `run.sh`.
