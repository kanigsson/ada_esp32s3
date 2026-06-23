# ext4 WRITE battery on an SD card over SDMMC — bare-metal Ada (ESP32-S3)

Exercises the **write API** of the pure-Ada filesystem (`ESP32S3.Ext4`) on a
**real `mkfs.ext4` SD card** over the **SDMMC** block driver, as one journaled
(JBD2) transaction. Each operation is asserted on-device; the card then passes
`e2fsck -f` clean on a Linux host, where the tree, the symlink target, the
hard-link inode sharing and the 1 MiB file's contents verify.

It is the write-path companion to the read-only
[`esp32s3_ext4_sdmmc`](../esp32s3_ext4_sdmmc) example, on the same board where
the card's **DAT3/CD** line is driven by a **CH422G** I2C expander.

```
[ext4w] mount (read-write): OK
[ext4w]   .. cleanup
[ext4w]   [PASS] create file
[ext4w]   [PASS] mkdir (is a directory)
[ext4w]   [PASS] file inside dir
[ext4w]   [PASS] big file size + head/tail pattern
[ext4w]   [PASS] hard link (same inode, nlink=2)
[ext4w]   [PASS] symlink (is a symlink, size=13)
[ext4w]   [PASS] rename (old gone, new present)
[ext4w]   [PASS] delete (gone)
[ext4w] all operations committed (journaled): OK
```

## What it does

| Op | API | Check |
|---|---|---|
| regular file | `Create_File` + `Write_File` | exists |
| subdirectory + file | `Mkdir`, `Create_File` | is-a-directory, child present |
| **1 MiB file** | `Write_File` | size + head/tail pattern (single-indirect map, >12 blocks) |
| **hard link** | `Link` | same inode, `nlink = 2` |
| **symbolic link** | `Symlink` | is-a-symlink, target length |
| rename / move | `Rename` | old gone, new present |
| delete | `Unlink` | gone |

## Preparing the card — must be NON-`metadata_csum`

Format the **whole device** (not a partition) and **without** `metadata_csum`:

```sh
sudo umount /dev/sdX*                              # if auto-mounted
sudo mkfs.ext4 -F -O ^metadata_csum /dev/sdX       # /dev/sdX  (NOT /dev/sdX1)
```

The pure-Ada FS *reads* `metadata_csum` filesystems but **refuses to write**
them (it does not yet recompute every metadata CRC32c), so it never leaves stale
checksums a host would flag. Writing a `metadata_csum` volume reports:

```
[ext4w] write FAILED: metadata_csum volume -- reformat: mkfs.ext4 -O ^metadata_csum
```

> **Run on a freshly-formatted card.** The example does a best-effort `cleanup`
> of its own leftovers so it can be re-run, but re-running write workloads on an
> already-written card is known to drift the superblock/group-descriptor free
> counts on the SDMMC path (`e2fsck` Pass 5). A fresh `mkfs` per run is
> `e2fsck`-clean. The filesystem logic itself is validated against the host
> `e2fsck` for all these ops — see `libs/esp32s3_hal/test/ext4_host`.

## Verifying on a host

```sh
sudo e2fsck -f /dev/sdX                            # clean, no errors
sudo mount -o ro /dev/sdX /mnt
ls -liR /mnt                                        # tree; hard link shares inode
readlink /mnt/ada_link                              # -> ada_write.txt
cmp <(python3 -c 'import sys;sys.stdout.buffer.write(bytes(i%251 for i in range(1<<20)))') \
    /mnt/ada_big.bin                                # 1 MiB pattern matches
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
  external PSRAM (`HEAP_PSRAM=1`).
- **Journaled.** A write goes through the cache; `Commit` writes the JBD2
  descriptor/data/commit blocks, sets the on-disk RECOVER barrier, checkpoints
  the dirty metadata, then clears RECOVER. Note that a file larger than the
  block cache is checkpointed by eviction (consistent on a clean unmount, not
  crash-atomic for the evicted data blocks).
- The write path uses **no nested-subprogram-access callbacks**: on this target
  a GNAT stack trampoline (emitted for `'Access` of an up-level-capturing nested
  subprogram) faults on the non-executable stack. The journal collects its
  write-set via the callback-free `Block_Cache.Dirty_Tags`.
- Both the FS and SDMMC use controlled / secondary-stack resources → **embedded
  / full** profiles only.
