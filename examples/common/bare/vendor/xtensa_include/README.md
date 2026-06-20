# Vendored Xtensa headers

These are the Xtensa assembler/HAL headers needed to compile the bare boot's
`highint5.S` (the level-5 GNARL tick + level-3 device-interrupt vectors). They are
vendored here so the repo builds with **no ESP-IDF install** — `bare_build.sh` uses
`-I.../vendor/xtensa_include` by default (set `IDF_PATH` to override with a live IDF
tree's headers).

## Contents (13 headers — `highint5.S`'s exact transitive closure)

- `xtensa_context.h`
- `xtensa/{coreasm,corebits,hal,xtensa-versions,xtruntime-frames}.h`
- `xtensa/config/{core,core-isa,core-matmap,specreg,system,tie-asm,tie}.h`

## Provenance

Copied verbatim from **ESP-IDF v5.4.4** (`~/esp/esp-idf`):
- `components/xtensa/include/` → `xtensa_context.h`, `xtensa/*.h`
- `components/xtensa/esp32s3/include/` → `xtensa/config/*.h` (the ESP32-S3 core config)

To regenerate (e.g. on an IDF version bump), re-copy that closure:
`xtensa-esp32-elf-gcc -M -I<idf>/components/xtensa/include \
  -I<idf>/components/xtensa/esp32s3/include highint5.S` lists the exact files.

## License

Permissively licensed, redistribution allowed:
- `xtensa/config/*.h` and the HAL/`xtruntime`/`coreasm` headers — **Tensilica Inc.**
  MIT-style license ("Permission is hereby granted, free of charge … to use, copy,
  modify, … distribute, sublicense, and/or sell copies").
- `xtensa_context.h` and the Espressif-authored bits — **Apache-2.0** (ESP-IDF).

Consistent with the other vendored IDF artifacts in `../` (`libxt_hal.a`,
`xtensa_objs/`, the 2nd-stage bootloader blobs).
