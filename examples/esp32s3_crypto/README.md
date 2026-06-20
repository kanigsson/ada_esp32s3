# Crypto — bare-metal Ada hardware SHA-1/224/256 + AES-128/256 (ESP32-S3, no FreeRTOS)

Self-test for the reusable **`ESP32S3.SHA`** and **`ESP32S3.AES`** hardware-crypto
drivers (in `libs/esp32s3_hal`) — no ESP-IDF, no FreeRTOS, on the Ada runtime.
The operations are deterministic, so they're checked against published test
vectors **with no wiring**.

```
[crypto] bare-metal hardware SHA-1/224/256 + AES-128/256 self-test (test vectors)
[crypto] SHA-1("abc")   vs FIPS-180 vector: PASS
[crypto] SHA-224("abc") vs FIPS-180 vector: PASS
[crypto] SHA-256("abc") vs FIPS-180 vector: PASS
[crypto] AES-128 encrypt vs FIPS-197 vector: PASS
[crypto] AES-128 decrypt round-trip: PASS
[crypto] AES-256 enc+dec vs FIPS-197 vector: PASS
```

## What it checks

- **SHA-1 / SHA-224 / SHA-256** of the string `"abc"` are computed by the hardware
  accelerator and compared to the FIPS-180 example digests (SHA-256 =
  `ba7816bf 8f01cfea … f20015ad`). All three share the 512-bit block and padding;
  only the MODE and digest length differ.
- **AES-128 ECB** of the FIPS-197 example (key `000102…0f`, plaintext
  `00112233…ff`) is encrypted by the hardware and compared to the expected
  ciphertext (`69c4e0d8…70b4c55a`), then decrypted back to the plaintext.
- **AES-256 ECB** of the FIPS-197 Appendix C.3 example (32-byte key) likewise
  encrypts to the published ciphertext (`8ea2b7ca…4b496089`) and decrypts back.

> **AES-192 is not available on the ESP32-S3 silicon.** Selecting it makes the
> hardware silently fall back to AES-128 on the first 16 key bytes (verified: it
> emitted the AES-128 ciphertext), so the driver intentionally offers only
> `Key_128` and `Key_256`. 192-bit keys exist only on the original ESP32. The
> operations enforce this with a `Pre => Supported_Key (Key)` contract (only 16-
> or 32-byte keys); a wrong-sized key is a contract violation rather than a silent
> AES-128 fallback. `Key_128` / `Key_256` callers satisfy it statically.

Matching the standard vectors proves the accelerators run correctly on silicon —
including the register byte order (the words are the little-endian packing of the
byte stream, which the hardware expects).

## Using the drivers

```ada
with ESP32S3.SHA;  with ESP32S3.AES;

D : constant ESP32S3.SHA.SHA256_Digest := ESP32S3.SHA.Hash_256 (Message);  -- or Hash_1 / Hash_224
C : constant ESP32S3.AES.Block := ESP32S3.AES.Encrypt_ECB (Key, Plain);    -- Key_128 or Key_256
P : constant ESP32S3.AES.Block := ESP32S3.AES.Decrypt_ECB (Key, C);
```

Each accelerator is a single shared resource serialised by a protected object, so
concurrent calls from different tasks are safe. No finalization, so they work
under every runtime profile.

## Build & flash

```sh
./x run esp32s3_crypto           # build + flash + monitor
```

Built as the **embedded** profile. The report prints over the USB-Serial-JTAG
console via the ROM `esp_rom_printf` glue in `main/glue.c`.
