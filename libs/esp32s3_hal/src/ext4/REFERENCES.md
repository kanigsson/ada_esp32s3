# `ESP32S3.Ext4` — references

This is a **pure-Ada reimplementation** of ext2/3/4 + the JBD2 journal. No C is
vendored here; the code conforms to the published ext4 / JBD2 **on-disk format**,
with [lwext4](https://github.com/gkostka/lwext4) as the structural model and
e2fsprogs / the Linux kernel as the correctness oracle.

## On-disk format (the authoritative specification)

- **ext4 Data Structures and Algorithms** — the canonical layout spec
  (superblock, block-group descriptors, inodes, extent trees, classic indirect
  block maps, linear + HTree directory entries, `metadata_csum`):
  <https://www.kernel.org/doc/html/latest/filesystems/ext4/>
  - Superblock: <https://www.kernel.org/doc/html/latest/filesystems/ext4/globals.html#super-block>
  - Block group descriptors: <https://www.kernel.org/doc/html/latest/filesystems/ext4/globals.html#block-group-descriptors>
  - Inodes: <https://www.kernel.org/doc/html/latest/filesystems/ext4/inodes.html>
  - Extents: <https://www.kernel.org/doc/html/latest/filesystems/ext4/dynamic.html#extent-tree>
  - Directory entries + HTree: <https://www.kernel.org/doc/html/latest/filesystems/ext4/dynamic.html#directory-entries>
  - Checksums (`metadata_csum`, CRC32c): <https://www.kernel.org/doc/html/latest/filesystems/ext4/overview.html#checksums>

- **JBD2 journal format** — big-endian; magic `0xC03B3998`; superblock,
  descriptor / commit / revoke blocks, block tags (classic / 64-bit / csum-v3):
  <https://www.kernel.org/doc/html/latest/filesystems/ext4/journal.html>

## Reference implementation (structural model)

- **lwext4** (portable C ext2/3/4): <https://github.com/gkostka/lwext4>
  - Package ↔ lwext4 mapping (see also the per-package header comments):

    | `ESP32S3.Ext4.*`        | lwext4 source            |
    |-------------------------|--------------------------|
    | `CRC32C`                | `ext4_crc32.c`           |
    | `Block_Cache`           | `ext4_bcache.c` / `ext4_blockdev.c` |
    | `Superblock`            | `ext4_super.c`           |
    | `Group_Desc` / `Bitmap` | `ext4_balloc.c` / `ext4_ialloc.c` |
    | `Inode`                 | `ext4_inode.c`           |
    | `Block_Map.Indirect`    | classic inode block map  |
    | `Block_Map.Extents`     | `ext4_extent.c`          |
    | `Dir` (linear)          | `ext4_dir.c`             |
    | (HTree read)            | `ext4_dir_idx.c`         |
    | `Journal`               | `ext4_journal.c`         |
    | `FS` / `Path` / `File` / `Writer` | `ext4.c` / `ext4_fs.c` |

## Correctness oracle

- **e2fsprogs** (`mke2fs`, `e2fsck`, `debugfs`) — the de-facto reference for
  checksum seeds, free-count accounting, link counts and journal recovery; used
  as the ground truth by the host harness:
  <https://git.kernel.org/pub/scm/fs/ext2/e2fsprogs.git>
- The Linux kernel's own `fs/ext4` + `fs/jbd2` (recovery semantics; cross-checked
  via `e2fsck -fy` replaying images this code wrote): <https://git.kernel.org/>

## How conformance is verified

A host test harness (kept in the development repository) builds the
(hardware-independent) filesystem with native x86 GNAT and runs it against real
`mke2fs` images, byte-comparing reads to the source files and validating every
mutation with `e2fsck -fn`; journal replay **and** commit are cross-checked
against the kernel's own `e2fsck -fy` recovery.
