/* esp32s3_rmt_loopback console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_rmt_banner(void)
{
    esp_rom_printf("[rmt] bare-metal RMT TX->RX single-pad loopback self-test (no wiring)\n");
}
void native_rmt_result(int sent, int received, int ok)
{
    esp_rom_printf("[rmt] loopback: sent=%d received=%d durations-match=%s  %s\n",
                   sent, received, ok ? "y" : "n", ok ? "PASS" : "FAIL");
}
void native_rmt_dump(int i, int lvl0, int d0, int lvl1, int d1)
{
    esp_rom_printf("[rmt]   got[%d] = {%d:%d, %d:%d}\n", i, lvl0, d0, lvl1, d1);
}
void native_rmt_done(void) { esp_rom_printf("[rmt] done.\n"); }
