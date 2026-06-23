/* esp32s3_ext4_write console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_w_banner(void)
{
    esp_rom_printf("[ext4w] ext4 WRITE test over SDMMC (creates /ada_write.txt)\n");
}

void native_w_card(int ok)
{
    esp_rom_printf("[ext4w] SD init: %s\n", ok ? "OK" : "FAILED");
}

void native_w_mount(int ok)
{
    esp_rom_printf("[ext4w] mount (read-write): %s\n", ok ? "OK" : "FAILED");
}

void native_w_write(int ok, const char *msg)
{
    if (ok) esp_rom_printf("[ext4w] create + write + commit (journaled): OK\n");
    else    esp_rom_printf("[ext4w] write FAILED: %s\n", msg);
}

void native_w_verify(int ok, int size, const char *content)
{
    esp_rom_printf("[ext4w] read-back: %s   %d bytes = \"%s\"\n",
                   ok ? "MATCH" : "MISMATCH", size, content);
}

void native_w_step(const char *s) { esp_rom_printf("[ext4w]   .. %s\n", s); }

void native_w_done(void)
{
    esp_rom_printf("[ext4w] done.  On a host: 'e2fsck -f /dev/sdX' should be "
                   "clean and /ada_write.txt readable.\n");
}
