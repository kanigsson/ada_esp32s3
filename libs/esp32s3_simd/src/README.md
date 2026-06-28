# ESP32S3.SIMD — vendored SIMD vector library

Vector kernels for the ESP32-S3's **PIE** SIMD extension (Xtensa LX7, 128-bit
`q0`–`q7` registers), with the inner loops written as **GNAT inline assembly**
(`System.Machine_Code`) inside the Ada bodies. Element families: `Integer_8`,
`Integer_16`, `Integer_32`, `IEEE_Float_32`. Application code `with`s the facade
`ESP32S3.SIMD`; the per-type kernels live in the children `ESP32S3.SIMD.I8`,
`.I16`, `.I32`, `.F32` (plus `.Helpers`).

> **Status: experimental / beta.** Correctness is validated for a subset of
> operations through the benchmark harness; edge cases and operation interactions
> are not systematically exercised. Do not rely on it in safety-critical contexts
> without independent verification.

## Provenance

Vendored from **[rowsail/ada-esp32-s3-simd](https://github.com/rowsail/ada-esp32-s3-simd)**,
which is itself based on the low-level SIMD implementation ideas of the upstream
**[zliu43/esp_simd](https://github.com/zliu43/esp_simd)** project.

The only change on vendoring is the package rename **`ESP32.S3.SIMD` →
`ESP32S3.SIMD`** (and the file names to match), so the tree sits under this repo's
HAL root package `ESP32S3` rather than redefining its own `ESP32`/`ESP32.S3`
parents. The kernel sources are otherwise unmodified.

## Building it here

Two ESP32-S3-specific facts make this build where the upstream Alire/ESP-IDF
skeleton did:

1. **Assembler.** The bundled Alire `xtensa-esp32-elf` assembler (an LX6 config)
   does not know the PIE `ee.*` opcodes. The repo already exports
   `XTENSA_GNU_CONFIG` to its S3 dynamic-config overlay
   (`crates/xtensa-dynconfig/.../xtensa_esp32s3.so`) for every compile, which adds
   them — so no extra setup is needed when building through `bare_build.sh`.
2. **Coprocessor.** The PIE SIMD unit is coprocessor **3** (`cop_ai`) on the S3.
   The bare runtime's `start.S` enables it (`CPENABLE = 16#09#` — CP0 FPU + CP3),
   otherwise the first `ee.*` instruction takes a coprocessor-disabled trap.

See `examples/esp32s3_simd` for an on-board benchmark, and the book chapter on
embedding assembly in Ada.
