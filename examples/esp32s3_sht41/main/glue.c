/* esp32s3_sht41 example-specific console helpers.  Bare-boot is shared in
   ../../common/bare/bare_glue.c.  The Ada SHT41 driver does all the I2C work;
   these format the report over the ROM USB-Serial-JTAG printf. */
extern int esp_rom_printf(const char *fmt, ...);

void native_sht_banner(void)
{
    esp_rom_printf("[sht] SHT41 temperature/humidity driver demo "
                   "(SDA=IO8 SCL=IO7)\n");
}

/* Serial number (presence check). */
void native_sht_serial(unsigned serial, int ok)
{
    esp_rom_printf("[sht] serial : 0x%08x  %s\n",
                   serial, ok ? "(SHT41 present)" : "(no ACK!)");
}

void native_sht_no_device(void)
{
    esp_rom_printf("[sht] no SHT41 found at 0x44 -- check wiring/power.\n");
}

/* Append a signed "D.DD" from a milli-unit value (1000 = 1.00). */
static char *put_fixed(char *p, int milli)
{
    int whole, frac;
    if (milli < 0) { *p++ = '-'; milli = -milli; }
    whole = milli / 1000;
    frac  = (milli % 1000) / 10;        /* two decimals */
    /* whole part */
    {
        char t[8]; int n = 0;
        do { t[n++] = (char) ('0' + whole % 10); whole /= 10; } while (whole);
        while (n) *p++ = t[--n];
    }
    *p++ = '.';
    *p++ = (char) ('0' + frac / 10);
    *p++ = (char) ('0' + frac % 10);
    return p;
}

/* One reading: temperature in m°C, humidity in m%RH. */
void native_sht_sample(int temp_mc, int hum_mrh)
{
    char line[64], *p = line;
    const char *pre = "[sht] T=";
    while (*pre) *p++ = *pre++;
    p = put_fixed(p, temp_mc);
    { const char *s = " C  RH="; while (*s) *p++ = *s++; }
    p = put_fixed(p, hum_mrh);
    *p++ = ' '; *p++ = '%';
    *p = '\0';
    esp_rom_printf("%s\n", line);
}

void native_sht_done(void) { esp_rom_printf("[sht] done.\n"); }
