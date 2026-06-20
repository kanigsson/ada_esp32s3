/* esp32s3_rtcio_hold console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_rtcio_banner(void)
{
    esp_rom_printf("[rtcio] bare-metal RTC-IO pad-hold self-test (no wiring)\n");
}
void native_rtcio_result(int after_set, int while_held, int after_release, int ok)
{
    esp_rom_printf("[rtcio] GPIO5: set=%d  cleared-while-held=%d  cleared-after-release=%d  %s\n",
                   after_set, while_held, after_release, ok ? "PASS" : "FAIL");
}
void native_rtcio_pull(int pullup_level, int pulldown_level, int ok)
{
    esp_rom_printf("[rtcio] GPIO6 RTC pull: pull-up reads=%d  pull-down reads=%d  %s\n",
                   pullup_level, pulldown_level, ok ? "PASS" : "FAIL");
}
void native_rtcio_done(void) { esp_rom_printf("[rtcio] done.\n"); }
