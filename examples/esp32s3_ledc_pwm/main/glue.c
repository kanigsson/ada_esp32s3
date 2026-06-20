/* esp32s3_ledc_pwm example-specific console helpers.  All bare-boot is shared in
   ../../common/bare/bare_glue.c.  The Ada driver does the LEDC register work and
   imports these as "native_ledc_*". */
extern int esp_rom_printf(const char *fmt, ...);

void native_ledc_banner(void)
{
    esp_rom_printf("[ledc] bare-metal LEDC PWM self-test (GPIO-sampled, no wiring)\n");
}

void native_ledc_result(int set_pct, int meas_pct_x10, int meas_hz, int ok)
{
    esp_rom_printf("[ledc] duty set=%d%%   measured=%d.%d%%   freq=%d Hz  %s\n",
                   set_pct, meas_pct_x10 / 10, meas_pct_x10 % 10, meas_hz,
                   ok ? "PASS" : "FAIL");
}

/* RAII channel handle: all 8 channels claimed, a 9th claim correctly fails, and
   after the handles leave scope (Finalize releases) a fresh claim succeeds. */
void native_ledc_raii(int eight, int ninth_failed, int reclaimed, int ok)
{
    esp_rom_printf("[ledc] raii: 8-claimed=%s 9th-rejected=%s reclaimed=%s  %s\n",
                   eight ? "y" : "n", ninth_failed ? "y" : "n",
                   reclaimed ? "y" : "n", ok ? "PASS" : "FAIL");
}

void native_ledc_done(void) { esp_rom_printf("[ledc] done.\n"); }
