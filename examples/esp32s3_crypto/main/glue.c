/* esp32s3_crypto console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_crypto_banner(void)
{
    esp_rom_printf("[crypto] bare-metal hardware SHA-1/224/256 + AES-128/256 self-test (test vectors)\n");
}
void native_crypto_sha1(int ok)   { esp_rom_printf("[crypto] SHA-1(\"abc\")   vs FIPS-180 vector: %s\n", ok ? "PASS" : "FAIL"); }
void native_crypto_sha224(int ok) { esp_rom_printf("[crypto] SHA-224(\"abc\") vs FIPS-180 vector: %s\n", ok ? "PASS" : "FAIL"); }
void native_crypto_sha(int ok) { esp_rom_printf("[crypto] SHA-256(\"abc\") vs FIPS-180 vector: %s\n", ok ? "PASS" : "FAIL"); }
void native_crypto_aes_enc(int ok) { esp_rom_printf("[crypto] AES-128 encrypt vs FIPS-197 vector: %s\n", ok ? "PASS" : "FAIL"); }
void native_crypto_aes_dec(int ok) { esp_rom_printf("[crypto] AES-128 decrypt round-trip: %s\n", ok ? "PASS" : "FAIL"); }
void native_crypto_aes256(int ok) { esp_rom_printf("[crypto] AES-256 enc+dec vs FIPS-197 vector: %s\n", ok ? "PASS" : "FAIL"); }
void native_crypto_done(void) { esp_rom_printf("[crypto] done.\n"); }
