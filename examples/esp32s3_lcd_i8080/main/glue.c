/* esp32s3_lcd_i8080 console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_lcd_banner(void)
{
    esp_rom_printf("[lcd] bare-metal LCD i80 8-bit parallel DMA-TX self-test (no wiring)\n");
}
void native_lcd_tx(int bytes, int done, int ok)
{
    esp_rom_printf("[lcd] dma transmit (%d bytes): trans-done=%d  %s\n",
                   bytes, done, ok ? "PASS" : "FAIL");
}
void native_lcd_clk(int set_khz, int meas_khz, int ok)
{
    esp_rom_printf("[lcd] pclk: set=%d kHz measured=%d kHz  %s\n",
                   set_khz, meas_khz, ok ? "PASS" : "FAIL");
}
void native_lcd_done(void) { esp_rom_printf("[lcd] done.\n"); }
