/* esp32s3_ext4_sdmmc console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_fs_banner(void)
{
    esp_rom_printf("[ext4] pure-Ada ext4 over SDMMC (DAT3 via CH422G IO4), read-only\n");
}

void native_fs_card(int ok)
{
    esp_rom_printf("[ext4] SD init: %s\n", ok ? "OK" : "FAILED");
}

void native_fs_mount(int ok, int block_size)
{
    esp_rom_printf("[ext4] mount: %s   block size = %d\n",
                   ok ? "OK" : "FAILED", block_size);
}

static const char *ftype_name(int t)
{
    switch (t) {            /* ext4 dir-entry file_type */
    case 1: return "file"; case 2: return "dir"; case 7: return "link";
    default: return "?";
    }
}

void native_fs_entry(const char *name, int ino, int ftype)
{
    esp_rom_printf("[ext4]   %-4s ino=%-6d %s\n", ftype_name(ftype), ino, name);
}

void native_fs_file(int ok, int size, const char *preview)
{
    if (!ok) { esp_rom_printf("[ext4] /hello.txt: not found\n"); return; }
    esp_rom_printf("[ext4] /hello.txt: %d bytes = \"%s\"\n", size, preview);
}

void native_fs_err(const char *stage)
{
    esp_rom_printf("[ext4] ERROR: %s\n", stage);
}

void native_fs_done(void) { esp_rom_printf("[ext4] done.\n"); }
