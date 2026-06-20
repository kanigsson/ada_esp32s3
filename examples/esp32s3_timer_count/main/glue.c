/* esp32s3_timer_count console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_timer_banner(void)
{
    esp_rom_printf("[timer] bare-metal general-purpose timer self-test\n");
}
void native_timer_count(int expected, int measured, int ok)
{
    esp_rom_printf("[timer] 1 MHz count over 50 ms: expected~%d measured=%d  %s\n",
                   expected, measured, ok ? "PASS" : "FAIL");
}
void native_timer_alarm(int fired, int elapsed_us, int ok)
{
    esp_rom_printf("[timer] alarm@30000: fired=%d at~%d us  %s\n",
                   fired, elapsed_us, ok ? "PASS" : "FAIL");
}
void native_timer_done(void) { esp_rom_printf("[timer] done.\n"); }
