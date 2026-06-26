/* esp32s3_pcf85063a example-specific console helpers.  All bare-boot (core
   bring-up, env entry, the L5 tick, clock) is shared in ../../common/bare/
   bare_glue.c.  The demo report uses the ROM USB-Serial-JTAG printf (the
   reliable console path for these bare examples); the Ada driver does all the
   register/I2C work and imports these as "native_rtc_*". */
extern int esp_rom_printf(const char *fmt, ...);

void native_rtc_banner(void)
{
    esp_rom_printf("[rtc] PCF85063A RTC driver demo "
                   "(SDA=IO8  SCL=IO7  INT=none)\n");
}

/* Outcome of a one-shot bus step: 0 probe, 1 reset, 2 set-time, 3 set-alarm. */
void native_rtc_step(int code, int ok)
{
    static const char *const name[] = { "probe", "reset", "set-time",
                                        "set-alarm" };
    const char *m = (code >= 0 && code <= 3) ? name[code] : "?";
    esp_rom_printf("[rtc] %-9s : %s\n", m, ok ? "OK" : "FAIL");
}

void native_rtc_no_device(void)
{
    esp_rom_printf("[rtc] no PCF85063A ACK at 0x51 -- check wiring/power.\n");
}

/* One calendar reading.  valid = chip's clock-integrity flag (oscillator did
   not stop since the last set). */
void native_rtc_time(int year, int mon, int day, int wday,
                     int hh, int mm, int ss, int valid)
{
    static const char *const dow[] = { "Sun", "Mon", "Tue", "Wed",
                                       "Thu", "Fri", "Sat" };
    const char *d = (wday >= 0 && wday <= 6) ? dow[wday] : "???";
    esp_rom_printf("[rtc] %s %04d-%02d-%02d %02d:%02d:%02d  (integrity %s)\n",
                   d, year, mon, day, hh, mm, ss, valid ? "OK" : "LOST");
}

/* The alarm latched.  by_int = the INT-pin ISR latched it (a real Int_Pin was
   wired and fired); otherwise it was found by polling AF over I2C. */
void native_rtc_alarm(int by_int)
{
    esp_rom_printf("[rtc] *** ALARM fired ***  (detected via %s)\n",
                   by_int ? "INT interrupt" : "I2C poll");
}

void native_rtc_done(void) { esp_rom_printf("[rtc] done.\n"); }
