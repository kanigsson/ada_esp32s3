/* Reusable console-log shim over the ROM printf.
 *
 * These are FIXED-signature (non-variadic) wrappers that the Ada package
 * ESP32S3.Log imports, so examples can format output in Ada without writing
 * their own glue.c.  Variadic esp_rom_printf cannot be imported portably from
 * Ada; each helper below formats exactly one already-typed value.  Compiled and
 * linked into every example by bare_build.sh (alongside bare_glue.c).
 */
extern int esp_rom_printf(const char *fmt, ...);

void hal_log_cstr(const char *s) { esp_rom_printf("%s", s); }   /* NUL-terminated */
void hal_log_int (int n)         { esp_rom_printf("%d", n); }   /* signed decimal */
void hal_log_uint(unsigned int n){ esp_rom_printf("%u", n); }   /* unsigned decimal */
void hal_log_hex (unsigned int n){ esp_rom_printf("%x", n); }   /* lowercase hex */
