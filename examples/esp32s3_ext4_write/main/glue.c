/* esp32s3_ext4_write console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_w_banner(void)
{
    esp_rom_printf("[ext4w] ext4 WRITE battery over SDMMC "
                   "(mkdir / big file / hardlink / symlink / rename / delete)\n");
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
    if (ok) esp_rom_printf("[ext4w] all operations committed (journaled): OK\n");
    else    esp_rom_printf("[ext4w] write FAILED: %s\n", msg);
}

void native_w_step(const char *s) { esp_rom_printf("[ext4w]   .. %s\n", s); }

/* Per-operation on-device assertion. */
void native_w_check(const char *label, int ok)
{
    esp_rom_printf("[ext4w]   [%s] %s\n", ok ? "PASS" : "FAIL", label);
}

void native_w_done(void)
{
    esp_rom_printf("[ext4w] done.  On a host: 'e2fsck -f /dev/sdX' should be "
                   "clean; verify the tree + readlink + big-file pattern.\n");
}
