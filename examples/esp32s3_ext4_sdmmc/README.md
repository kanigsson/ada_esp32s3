# ext4 on an SD card over SDMMC — bare-metal Ada (ESP32-S3)

Mounts a **real `mkfs.ext4` SD card** with the pure-Ada filesystem
(`ESP32S3.Ext4`) over the **SDMMC** block driver, on a board where the card's
**DAT3/CD** line is driven by a **CH422G** I2C expander. Read-only: it lists the
root directory and reads `/hello.txt`. It never writes.

```
[ext4] SD init: OK
[ext4] mount: OK   block size = 4096
[ext4]   dir  ino=2      .
[ext4]   dir  ino=2      ..
[ext4]   dir  ino=11     lost+found
[ext4]   file ino=13     hello.txt
[ext4]   dir  ino=1179649 subdir
[ext4] /hello.txt: 36 bytes = "Hello from pure-Ada ext4 over SDMMC."
```

This is the **first on-card bring-up of the pure-Ada ext4 FS** — its
[README](../../libs/esp32s3_hal/src/ext4/README.md) had only ever verified it
host-native (against `e2fsck`) and over the never-on-card-tested SD-SPI path.

## How it fits together

```
ESP32S3.Ext4.FS  (mount / Lookup / Stat / Iterate / Read_File)
   │
ESP32S3.Block_Dev  (Read/Write a 512-byte sector + Count)
   │
ESP32S3.Block_Dev.SDMMC_Source   ← the new adapter
   │
ESP32S3.SDMMC      (Read_Block / Capacity_Blocks; 1-bit, High Speed 50 MHz)
   │
SD card  (DAT3/CD held high by ESP32S3.CH422G IO4)
```

`SDMMC_Source` (in `libs/esp32s3_hal/src/ext4/`) is the block-device adapter the
abstraction had reserved a slot for. Unlike the SD-SPI source it reports the
card's **true sector count** (`Capacity_Blocks` from the CSD).

## Wiring

| Signal | Pin |
|---|---|
| SDMMC CLK / CMD / D0 | **IO12 / IO11 / IO13** (1-bit) |
| SD DAT3 / CD | **CH422G IO4** (held high) |
| CH422G I2C | **SDA=IO8 SCL=IO9** (I2C0) |

## Preparing the card

Format the **whole device** (not a partition), so the ext4 superblock is at the
standard offset (LBA 2 of the device):

```sh
sudo umount /dev/sdX*                       # if auto-mounted
sudo mkfs.ext4 -F -L SDCARD /dev/sdX        # /dev/sdX  (NOT /dev/sdX1)
sudo mount /dev/sdX /mnt
echo "Hello from pure-Ada ext4 over SDMMC" | sudo tee /mnt/hello.txt
sudo mkdir /mnt/subdir
sync && sudo umount /mnt
```

Default `mkfs.ext4` is fine — the FS reads `metadata_csum` filesystems and
verifies the checksums on read.

## Build / flash / run

```sh
./x build ext4_sdmmc
./x flash ext4_sdmmc -p /dev/ttyACM0
./x run   ext4_sdmmc -p /dev/ttyACM0
```

## Notes

- The FS block cache lives on the heap — `build.sh` sets a 256 KB heap and the
  example mounts with `Cache_Blocks => 16` (16 × 4 KB).
- Read-only here; the pure-Ada FS also supports writes/journaling on
  non-`metadata_csum` filesystems (see the `ESP32S3.Ext4` README).
- Both the FS and SDMMC use controlled/secondary-stack resources → **embedded /
  full** profiles only.
