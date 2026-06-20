/* esp32s3_adc_read console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_adc_banner(void)
{
    esp_rom_printf("[adc] bare-metal SAR ADC one-shot self-test (drive+sense one pad, no wiring)\n");
}
void native_adc_result(int high_code, int low_code, int ok)
{
    esp_rom_printf("[adc] ADC1 ch0: drive-high=%d  drive-low=%d  %s\n",
                   high_code, low_code, ok ? "PASS" : "FAIL");
}
void native_adc_dbg(int cal_code, int done)
{
    esp_rom_printf("[adc]   cal_code=%d  last_done=%d\n", cal_code, done);
}
void native_adc_done(void) { esp_rom_printf("[adc] done.\n"); }
