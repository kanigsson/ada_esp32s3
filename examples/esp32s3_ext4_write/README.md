# ext4 WRITE test on an SD card over SDMMC — bare-metal Ada (ESP32-S3)

Creates a file on a **real `mkfs.ext4` SD card** with the pure-Ada filesystem
(`ESP32S3.Ext4`) over the **SDMMC** block driver, as one **journaled (JBD2)
transaction**, then reads it back and verifies it byte-for-byte. The card can
then be taken to a Linux host: `e2fsck -f` is clean and the file is readable.

It is the write-path companion to the read-only
[`esp32s3_ext4_sdmmc`](../esp32s3_ext4_sdmmc) example, on the same board where
the card's **DAT3/CD** line is driven by a **CH422G** I2C expander.

```
[ext4w] SD init: OK
[ext4w] mount (read-write): OK
[ext4w]   .. unlink-if-present
[ext4w]   .. create_file
[ext4w]   .. write_file
[ext4w]   .. commit
[ext4w]   .. committed
[ext4w] create + write + commit (journaled): OK
[ext4w] read-back: MATCH   46 bytes = "Written by ESP32-S3 pure-Ada ext4 over SDMMC!."
[ext4w] done.  On a host: 'e2fsck -f /dev/sdX' should be clean and /ada_write.txt readable.
```

The test is repeatable: it unlinks a leftover `/ada_write.txt` (committing the
removal) before re-creating it.

## Preparing the card — must be NON-`metadata_csum`

Format the **whole device** (not a partition) and **without** `metadata_csum`:

```sh
sudo umount /dev/sdX*                              # if auto-mounted
sudo mkfs.ext4 -F -O ^metadata_csum /dev/sdX       # /dev/sdX  (NOT /dev/sdX1)
```

The pure-Ada FS *reads* `metadata_csum` filesystems (verifying the checksums),
but **refuses to write** them: it does not yet recompute every metadata CRC32c,
so it never leaves stale checksums a host would flag. Writing to a
`metadata_csum` volume reports:

```
[ext4w] write FAILED: metadata_csum volume -- reformat: mkfs.ext4 -O ^metadata_csum
```

On a `^metadata_csum` volume the FS's writes are validated against `e2fsck` in
the host test harness, so the round-trip is host-readable and `e2fsck`-clean.

## Verifying on a host

```sh
sudo e2fsck -f /dev/sdX                            # clean, no errors
sudo mount /dev/sdX /mnt && cat /mnt/ada_write.txt # the written string
sudo umount /mnt
```

## Wiring

| Signal | Pin |
|---|---|
| SDMMC CLK / CMD / D0 | **IO12 / IO11 / IO13** (1-bit) |
| SD DAT3 / CD | **CH422G IO4** (held high) |
| CH422G I2C | **SDA=IO8 SCL=IO9** (I2C0) |

## Build / flash / run

```sh
./x build ext4_write
./x flash ext4_write -p /dev/ttyACM0
./x run   ext4_write -p /dev/ttyACM0
```

## Notes

- **Heap in PSRAM.** The journal commit allocates a transaction buffer (~64 KB)
  on top of the block cache, so `build.sh` puts the heap arena in the 8 MB
  external PSRAM (`HEAP_PSRAM=1`) rather than the small internal SRAM pool.
- **Journaled.** A write goes through the cache; `Commit` writes the JBD2
  descriptor/data/commit blocks, sets the on-disk RECOVER barrier, checkpoints
  the dirty metadata to its final locations, then clears RECOVER — so an
  interrupted write recovers forward (or rolls back) like the kernel's ext4.
- The write/commit path uses **no nested-subprogram-access callbacks**: on this
  target a GNAT stack trampoline (emitted for `'Access` of a nested subprogram
  that captures up-level state) faults on the non-executable stack. The journal
  collects its write-set via the callback-free `Block_Cache.Dirty_Tags`.
- Both the FS and SDMMC use controlled / secondary-stack resources → **embedded
  / full** profiles only.
