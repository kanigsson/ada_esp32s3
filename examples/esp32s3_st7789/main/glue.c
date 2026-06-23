/* esp32s3_st7789 example-specific console helpers.  Bare-boot is shared in
   ../../common/bare/bare_glue.c.  The Ada ST7789 driver does all the SPI work;
   the panel itself is the real output (write-only -- nothing to read back). */
extern int esp_rom_printf(const char *fmt, ...);

void native_st_banner(void)
{
    esp_rom_printf("[lcd] ST7789 240x240 SPI display demo "
                   "(SPI2 sclk=12 mosi=13 dc=16 cs=10, bl=6)\n");
}

void native_st_step(int code)
{
    static const char *const n[] = {
        "backlight + setup", "init", "fill red", "fill green", "fill blue",
        "colour bars", "centre box" };
    const char *m = (code >= 0 && code <= 6) ? n[code] : "?";
    esp_rom_printf("[lcd] %s\n", m);
}

void native_st_done(void)
{
    esp_rom_printf("[lcd] done -- check the panel.\n");
}
