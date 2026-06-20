/* esp32s3_sdm_output console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_sdm_banner(void)
{
    esp_rom_printf("[sdm] bare-metal SDM sigma-delta density self-test (GPIO-sampled, no wiring)\n");
}
void native_sdm_result(int set_pct, int meas_pct_x10, int ok)
{
    esp_rom_printf("[sdm] density set=%d%%   measured=%d.%d%%   %s\n",
                   set_pct, meas_pct_x10 / 10, meas_pct_x10 % 10, ok ? "PASS" : "FAIL");
}
void native_sdm_raii(int eight, int ninth_failed, int reclaimed, int ok)
{
    esp_rom_printf("[sdm] raii: 8-claimed=%s 9th-rejected=%s reclaimed=%s  %s\n",
                   eight ? "y" : "n", ninth_failed ? "y" : "n",
                   reclaimed ? "y" : "n", ok ? "PASS" : "FAIL");
}
void native_sdm_done(void) { esp_rom_printf("[sdm] done.\n"); }
