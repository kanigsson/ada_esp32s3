/* esp32s3_pcnt_count console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_pcnt_banner(void)
{
    esp_rom_printf("[pcnt] bare-metal PCNT pulse-counter self-test (no wiring)\n");
}
void native_pcnt_result(int pulses, int counted, int ok)
{
    esp_rom_printf("[pcnt] count: pulses-driven=%d counted=%d  %s\n",
                   pulses, counted, ok ? "PASS" : "FAIL");
}
void native_pcnt_raii(int four, int fifth_failed, int reclaimed, int ok)
{
    esp_rom_printf("[pcnt] raii: 4-claimed=%s 5th-rejected=%s reclaimed=%s  %s\n",
                   four ? "y" : "n", fifth_failed ? "y" : "n",
                   reclaimed ? "y" : "n", ok ? "PASS" : "FAIL");
}
void native_pcnt_done(void) { esp_rom_printf("[pcnt] done.\n"); }
