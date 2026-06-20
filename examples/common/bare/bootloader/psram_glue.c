/* Freestanding bits the vendored octal-PSRAM + MSPI-timing objects reference,
 * so the bootloader can call esp_psram_impl_enable() directly (Stage 1.2).
 * Mirrors the app-side psram glue stubs, plus memcpy (the bootloader has no
 * runtime).  esp_log is suppressed (level 0); the leaf stubs are no-ops with the
 * same justification as the app side (the per-CPU/cache/flash-reg work is either
 * unneeded here or done elsewhere). */
#include <stdint.h>
#include <stddef.h>

extern int esp_rom_printf(const char *fmt, ...);

void *memcpy(void *d, const void *s, size_t n)
{ unsigned char *a = d; const unsigned char *b = s; while (n--) *a++ = *b++; return d; }
void *memset(void *d, int c, size_t n)
{ unsigned char *a = d; while (n--) *a++ = (unsigned char) c; return d; }
int memcmp(const void *a, const void *b, size_t n)
{ const unsigned char *x = a, *y = b; while (n--) { if (*x != *y) return *x - *y; x++; y++; } return 0; }

void abort(void) { esp_rom_printf("[boot] abort()\n"); for (;;) { } }
void __assert_func(const char *f, int l, const char *fn, const char *e)
{ esp_rom_printf("[boot] assert %s:%d %s: %s\n", f, l, fn, e); abort(); }

/* leaf stubs the vendored objects reference (no IDF services in the bootloader) */
int  bootloader_flash_is_octal_mode_enabled(void) { return 0; }       /* flash is DIO */
void esp_cache_freeze_ext_mem_cache(void)         { }
void esp_cache_unfreeze_ext_mem_cache(void)       { }
uint64_t esp_gpio_reserve(uint64_t mask)          { (void) mask; return 0; }
uint32_t esp_log_timestamp(void)                  { return 0; }
void spi_flash_set_rom_required_regs(void)        { }
void spi_flash_set_vendor_required_regs(void)     { }
int  esp_log_default_level = 0;                                       /* suppress logs */
