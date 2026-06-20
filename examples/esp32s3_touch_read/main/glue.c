/* esp32s3_touch_read console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_touch_banner(void)
{
    esp_rom_printf("[touch] bare-metal capacitive-touch read self-test (no wiring)\n");
}
void native_touch_chan(int ch, int gpio, int raw)
{
    esp_rom_printf("[touch] channel %d (GPIO%d): raw count = %d\n", ch, gpio, raw);
}
void native_touch_result(int ok)
{
    esp_rom_printf("[touch] baseline counts non-zero + distinct: %s\n",
                   ok ? "PASS" : "FAIL");
}
void native_touch_thresh(int baseline, int now, int untouched, int shifted, int ok)
{
    esp_rom_printf("[touch] ch1: baseline=%d now=%d  Touched(baseline)=%d Touched(baseline+200k)=%d  %s\n",
                   baseline, now, untouched, shifted, ok ? "PASS" : "FAIL");
}
void native_touch_done(void) { esp_rom_printf("[touch] done.\n"); }
