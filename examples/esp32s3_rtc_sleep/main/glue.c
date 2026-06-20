/* esp32s3_rtc_sleep console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

static const char *cause_name(int c)
{
    switch (c) { case 0: return "power-on"; case 1: return "deep-sleep-timer";
                 case 2: return "deep-sleep-gpio"; default: return "other-reset"; }
}
void native_rtc_banner(void)
{
    esp_rom_printf("[rtc] bare-metal RTC deep-sleep + retained-memory self-test\n");
}
void native_rtc_boot(int cause, int count)
{
    esp_rom_printf("[rtc] boot: wake=%s  retained boot-count=%d\n",
                   cause_name(cause), count);
}
void native_rtc_sleeping(int ms)
{
    esp_rom_printf("[rtc] entering deep sleep for ~%d ms (console drops until wake)...\n", ms);
}
void native_rtc_final(int count, int cause, int ok)
{
    esp_rom_printf("[rtc] FINAL: boot-count=%d last-wake=%s  %s\n",
                   count, cause_name(cause), ok ? "PASS" : "FAIL");
}
