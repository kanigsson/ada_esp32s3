# esp_elf2image — an Ada `esptool elf2image`

A small **host** tool (native Ada, built with the Alire `gnat_native`) that converts
a linked `app.elf` into an ESP32-S3 flash image `app.bin`, replacing the
`elf2image` half of esptool in the build. `bare_build.sh` uses it by default
(set `ESP_USE_ESPTOOL=1` to fall back to esptool).

It reproduces esptool's algorithm **byte-for-byte** — verified `cmp`-identical to
`esptool --chip esp32s3 elf2image --flash_mode dio --flash_freq 80m --flash_size 2MB`
across all the `esp32s3_*` examples, and the resulting image boots on HW.

## What it does

1. Source segments = the ELF's allocated `PROGBITS` sections, merged where
   contiguous, each data length padded up to a multiple of 4.
2. 24-byte header: 8-byte common (`magic 0xE9`, segment count, `dio`, `2MB|80m`,
   entry) + 16-byte extended (`chip_id=9`, `wp_pin=0xEE`, `max_rev_full=0xFFFF`,
   `hash_appended=1`).
3. Flash (IROM/DROM) segments aligned to 64 KB, with the RAM segments written
   **interleaved as the alignment padding** (then a zero PADDING segment for the
   remainder) — exactly esptool's scheme.
4. XOR checksum (seed `0xEF`) as the last byte of a 16-aligned block.
5. SHA-256 of the whole image appended (`src/sha256.adb`).

## Build / run

```sh
gprbuild -P esp_elf2image.gpr           # needs Alire gnat_native + gprbuild
./esp_elf2image app.elf app.bin
```

The flash parameters (`dio` / `80m` / `2MB`, chip = ESP32-S3) are fixed to match
every example's `bare_build.sh`; change the constants at the top of
`src/esp_elf2image.adb` if a project needs different ones.

## Scope

This covers esptool's **`elf2image`** (offline image packaging). Flashing
(`write_flash`, the serial-bootloader protocol) is still done by esptool in
`bare_flash.sh` / `parallel_sweep.py` — a possible future Ada port.
