/* esp32s3_twai_loopback console helpers.  Shared bare-boot in ../../common/bare. */
extern int esp_rom_printf(const char *fmt, ...);

void native_twai_banner(void)
{
    esp_rom_printf("[twai] bare-metal TWAI (CAN) self-test loopback (no wiring)\n");
}
void native_twai_result(int extended, int remote, int got, int id, int len,
                        int data_ok, int ok)
{
    esp_rom_printf("[twai] %s %s self-rx: got=%d id=0x%x len=%d match=%s  %s\n",
                   extended ? "extended(29-bit)" : "standard(11-bit)",
                   remote ? "remote(RTR)" : "data      ",
                   got, id, len, data_ok ? "y" : "n", ok ? "PASS" : "FAIL");
}
void native_twai_done(void) { esp_rom_printf("[twai] done.\n"); }
