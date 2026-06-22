/* esp32s3_gps example-specific console helpers.  Bare-boot is shared in
   ../../common/bare/bare_glue.c.  The Ada GPS driver does all the UART + NMEA
   work; these just format the report over the ROM USB-Serial-JTAG printf.

   Same ROM-printf caveats as the other examples: no '+' flag, a ~6-conversion
   cap, and a non-blocking 64-byte FIFO -- so the sample line is built into a
   buffer and emitted with one "%s", kept under 64 bytes, and the Ada side
   spaces the back-to-back lines. */
extern int esp_rom_printf(const char *fmt, ...);

void native_gps_banner(void)
{
    esp_rom_printf("[gps] NMEA GPS driver demo (UART0 rx=44 tx=43)\n");
    esp_rom_printf("[gps] self-test: inject canned NMEA, check store\n");
}

/* One self-test check.  code selects the name; ok = PASS/FAIL. */
void native_gps_check(int code, int ok)
{
    static const char *const n[] = {
        "gga accept", "position", "fix info", "utc time",
        "rmc accept", "date", "velocity", "bad-cks rej",
        "zda t/date", "gll pos", "vtg vel", "gsv view", "gsa dop",
        "gsv sats" };
    const char *m = (code >= 0 && code <= 13) ? n[code] : "?";
    esp_rom_printf("[gps] %-11s : %s\n", m, ok ? "PASS" : "FAIL");
}

void native_gps_live_hdr(void)
{
    esp_rom_printf("[gps] live (UART0 @ 9600) -- waiting for sentences...\n");
}

static char *put_str(char *p, const char *s) { while (*s) *p++ = *s++; return p; }

static char *put_uint(char *p, unsigned v)
{
    char t[12]; int n = 0;
    do { t[n++] = (char) ('0' + v % 10u); v /= 10u; } while (v);
    while (n) *p++ = t[--n];
    return p;
}

static char *put_int(char *p, int v)
{
    if (v < 0) { *p++ = '-'; return put_uint(p, (unsigned) -v); }
    return put_uint(p, (unsigned) v);
}

/* 1e-7 degrees -> "[-]D.DDDDDDD" (7 fractional digits). */
static char *put_deg(char *p, int e7)
{
    unsigned u = (e7 < 0) ? (unsigned) -e7 : (unsigned) e7;
    int div;
    if (e7 < 0) *p++ = '-';
    p = put_uint(p, u / 10000000u);
    *p++ = '.';
    for (div = 1000000; div >= 1; div /= 10)
        *p++ = (char) ('0' + (u / div) % 10u);
    return p;
}

static char *put2(char *p, int v)
{
    *p++ = (char) ('0' + (v / 10) % 10);
    *p++ = (char) ('0' + v % 10);
    return p;
}

/* One live status line, leading with the live UTC clock (which ZDA refreshes
   even before a position fix; --:--:-- when stale).  Position is shown only when
   pos_fresh (a recent live fix); otherwise the acquisition view from GSV/GSA is
   shown (satellites in view, strongest C/N0, 2D/3D mode), so you can watch it
   acquire and a stale leftover never masks the truth. */
void native_gps_live(int time_valid, int hh, int mm, int ss, int pos_fresh,
                     int lat_e7, int lon_e7, int in_view, int max_snr,
                     int fix_type)
{
    char line[80], *p = line;
    p = put_str(p, "[gps] UTC=");
    if (time_valid) {
        p = put2(p, hh); *p++ = ':'; p = put2(p, mm); *p++ = ':'; p = put2(p, ss);
    } else {
        p = put_str(p, "--:--:--");
    }
    if (pos_fresh) {
        p = put_str(p, " lat="); p = put_deg(p, lat_e7);
        p = put_str(p, " lon="); p = put_deg(p, lon_e7);
    } else {
        p = put_str(p, " view="); p = put_int(p, in_view);
        p = put_str(p, " snr="); p = put_int(p, max_snr);
        p = put_str(p, " ");
        p = put_str(p, fix_type == 2 ? "3D" : fix_type == 1 ? "2D" : "no-fix");
    }
    *p = '\0';
    esp_rom_printf("%s\n", line);
}

/* Echo the most recent raw NMEA sentence (s is not NUL-terminated; n chars).
   Clipped to stay within the 64-byte console FIFO. */
void native_gps_raw(const char *s, int n)
{
    char line[80], *p = line;
    int i, lim = n > 52 ? 52 : n;
    p = put_str(p, "[gps] raw: ");
    for (i = 0; i < lim; i++) *p++ = s[i];
    if (n > lim) { *p++ = '.'; *p++ = '.'; }
    *p = '\0';
    esp_rom_printf("%s\n", line);
}

void native_gps_sat_hdr(int count)
{
    esp_rom_printf("[gps] satellites in view: %d\n", count);
}

/* One satellite: sys 0..5 = GP/GL/GA/BD/QZ/Other. */
void native_gps_sat(int sys, int prn, int el, int az, int snr)
{
    static const char *const s[] = { "GP", "GL", "GA", "BD", "QZ", "??" };
    const char *ss = (sys >= 0 && sys <= 5) ? s[sys] : "??";
    char line[80], *p = line;
    p = put_str(p, "[gps]   ");
    p = put_str(p, ss); p = put_int(p, prn);
    p = put_str(p, " el="); p = put_int(p, el);
    p = put_str(p, " az="); p = put_int(p, az);
    p = put_str(p, " snr="); p = put_int(p, snr);
    *p = '\0';
    esp_rom_printf("%s\n", line);
}

void native_gps_done(void) { esp_rom_printf("[gps] done.\n"); }
