/* Freestanding mem* + abort the bootloader's C and ZFP-Ada code need (no runtime
 * is linked).  The vendored-blob leaf stubs that used to live here are gone with
 * the blobs -- the octal-PSRAM bring-up is now from-source (psram_impl_src.c +
 * mspi_timing_src.c) and calls only ROM functions. */
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
