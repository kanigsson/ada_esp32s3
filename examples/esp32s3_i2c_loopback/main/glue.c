/* esp32s3_i2c_loopback example-specific console helpers.  All bare-boot (core
   bring-up, env entry, the L5 tick, clock) is shared in ../../common/bare/
   bare_glue.c.  The self-test report uses the ROM USB-Serial-JTAG printf (the
   reliable console path for these bare examples); the Ada driver does all the
   register work and imports these as "native_i2c_*". */
extern int esp_rom_printf(const char *fmt, ...);

void native_i2c_banner(void)
{
    esp_rom_printf("[i2c] bare-metal I2C master hardware self-test "
                   "(no wiring, no device)\n");
}

void native_i2c_verdict(int test, int ok)
{
    esp_rom_printf("[i2c] test%d: %s\n", test, ok ? "PASS" : "FAIL");
}

void native_i2c_done(void) { esp_rom_printf("[i2c] done.\n"); }
