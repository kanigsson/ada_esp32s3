/* esp32s3_gdma_copy example-specific console helpers.  All bare-boot is shared in
   ../../common/bare/bare_glue.c.  The Ada driver does the DMA register work and
   imports these as "native_gdma_*". */
extern int esp_rom_printf(const char *fmt, ...);

void native_gdma_banner(void)
{
    esp_rom_printf("[gdma] bare-metal GDMA mem-to-mem + RAII channel self-test\n");
}

void native_gdma_copy(int ok)
{
    esp_rom_printf("[gdma] mem2mem copy (64 B): %s\n", ok ? "PASS" : "FAIL");
}

/* RAII channel handle: all 5 channels claimed, a 6th claim correctly fails, and
   after the handles leave scope (Finalize releases) a fresh claim succeeds. */
void native_gdma_raii(int five_claimed, int sixth_failed, int reclaimed, int ok)
{
    esp_rom_printf("[gdma] raii: 5-claimed=%s 6th-rejected=%s reclaimed=%s  %s\n",
                   five_claimed ? "y" : "n", sixth_failed ? "y" : "n",
                   reclaimed ? "y" : "n", ok ? "PASS" : "FAIL");
}

void native_gdma_done(void) { esp_rom_printf("[gdma] done.\n"); }
