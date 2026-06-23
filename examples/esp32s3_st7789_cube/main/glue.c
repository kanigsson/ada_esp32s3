/* esp32s3_st7789_cube example console helpers.  Bare-boot is shared in
   ../../common/bare/bare_glue.c.  The panel is the real output; the console
   just narrates startup and the occasional frame-rate. */
extern int esp_rom_printf(const char *fmt, ...);

void native_cube_banner(void)
{
    esp_rom_printf("[cube] bouncing solid-colour 3D cube -> ST7789 240x240\n");
    esp_rom_printf("[cube]   SPI2 sclk=12 mosi=13 dc=16 cs=10 bl=6\n");
}

void native_cube_fps(int fps) { esp_rom_printf("[cube] ~%d fps\n", fps); }
