/* esp32s3_gps_display example console helpers.  Bare-boot is shared in
   ../../common/bare/bare_glue.c.  The panel is the real output; the console
   just mirrors what's pushed to the display so a live run can be verified over
   serial too. */
extern int esp_rom_printf(const char *fmt, ...);

void native_gd_banner(void)
{
    esp_rom_printf("[gps-disp] GPS -> ST7789: lat/lon/UTC on a 240x240 panel\n");
    esp_rom_printf("[gps-disp]   GPS  UART0 rx=44 tx=43 9600\n");
    esp_rom_printf("[gps-disp]   LCD  SPI2  sclk=12 mosi=13 dc=16 cs=10 bl=6\n");
}

/* s = the exact text line pushed to one display row (already framed by Ada). */
void native_gd_row(const char *s)
{
    esp_rom_printf("[gps-disp] %s\n", s);
}

void native_gd_tick(int n) { esp_rom_printf("[gps-disp] --- tick %d ---\n", n); }
