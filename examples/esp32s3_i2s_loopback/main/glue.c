/* esp32s3_i2s_loopback example-specific console helpers.  All bare-boot is shared
   in ../../common/bare/bare_glue.c.  The Ada driver does the I2S register work and
   imports these as "native_i2s_*". */
extern int esp_rom_printf(const char *fmt, ...);

void native_i2s_banner(void)
{
    esp_rom_printf("[i2s] bare-metal I2S full-duplex DMA loopback self-test (no wiring)\n");
}

void native_i2s_result(int n, int ok)
{
    esp_rom_printf("[i2s] full-duplex loopback (%d samples): %s\n", n, ok ? "PASS" : "FAIL");
}

void native_i2s_done(void) { esp_rom_printf("[i2s] done.\n"); }
