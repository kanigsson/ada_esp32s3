/* esp32s3_ext4 console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_ext4_banner(void)
{
    esp_rom_printf("[ext4] bare-metal pure-Ada ext4 over SD-over-SPI (needs a wired ext4 card)\n");
}
void native_ext4_card(int status)
{
    esp_rom_printf("[ext4] SD card init: %s\n", status == 0 ? "OK" : "FAILED");
}
void native_ext4_mount(int ok, int block_size)
{
    esp_rom_printf("[ext4] mount: %s   block size = %d\n", ok ? "OK" : "FAILED", block_size);
}
void native_ext4_read(int ok, int b0, int b1, int b2, int b3)
{
    esp_rom_printf("[ext4] read /hello.txt: %s   first bytes = %02x %02x %02x %02x\n",
                   ok ? "OK" : "FAILED", b0, b1, b2, b3);
}
void native_ext4_done(void) { esp_rom_printf("[ext4] done.\n"); }
