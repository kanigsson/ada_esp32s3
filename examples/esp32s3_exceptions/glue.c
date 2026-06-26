/* esp32s3_exceptions console glue.  The demo body prints via Ada.Text_IO (the
   runtime routes it to the USB-serial console).  Only the custom last-chance
   handler uses this helper, because it runs in the fragile state just after an
   exception has escaped everything -- esp_rom_printf is always available.
   All bare-boot is shared in ../../common/bare/. */
extern int esp_rom_printf(const char *fmt, ...);

/* Print a NUL-terminated string followed by a newline. */
void native_exc_puts(const char *s)
{
    esp_rom_printf("%s\n", s);
}
