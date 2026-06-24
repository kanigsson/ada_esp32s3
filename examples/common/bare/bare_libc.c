/* Minimal freestanding libc for the IDF-free embedded/full RTS profiles.  GNAT's
 * runtime (exceptions, finalization, secondary stack) references a handful of C
 * library symbols that newlib supplied under ESP-IDF; the Alire toolchain's
 * newlib is big-endian and we link no libc, and the ESP32-S3 ROM does not export
 * these, so provide tiny versions here.  Paired with bare_heap.c's allocator and
 * compiled only when an example's build.sh sets HEAP_SIZE. */
#include <stdint.h>
#include <stddef.h>

/* memcpy/memmove/memset/memcmp now live in Ada (boot/bare_mem.adb, linked as
 * bare_mem.o); see that unit for the weak-symbol rationale.  The remaining
 * string/atoi/getenv/write/abort glue is still here pending its own Ada port. */

size_t strlen(const char *s)
{
    const char *p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) { a++; b++; }
    return (int)(uint8_t)*a - (int)(uint8_t)*b;
}

/* The full RTS closure pulls a few more newlib bits.  getenv has no environment
 * on bare metal; write routes bytes to the ROM console (esp_rom_printf) so any
 * runtime path writing to fd 1/2 still reaches the USB-JTAG console. */
extern int esp_rom_printf(const char *fmt, ...);

int atoi(const char *s)
{
    int sign = 1, v = 0;
    while (*s == ' ' || *s == '\t') s++;
    if (*s == '-') { sign = -1; s++; } else if (*s == '+') s++;
    while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0');
    return sign * v;
}

char *getenv(const char *name) { (void) name; return (char *) 0; }

int write(int fd, const void *buf, unsigned int n)
{
    const unsigned char *p = buf;
    (void) fd;
    for (unsigned int i = 0; i < n; i++) esp_rom_printf("%c", p[i]);
    return (int) n;
}

/* The runtime's Last_Chance_Handler / a failed allocation reach abort(); reset the
 * board via the shared esp_restart (defined in stubs.c).  The trailing loop makes
 * abort non-returning (it is a noreturn builtin). */
extern void esp_restart(void);

void abort(void)
{
    esp_restart();
    for (;;) { }
}

/* Register the DWARF unwind frames for ZCX exceptions.  There is no crtbegin/
 * frame_dummy on this bare target, so call libgcc's __register_frame on the
 * linker-bracketed .eh_frame block (sections.ld __eh_frame_start, 0-terminated)
 * once at startup.  Overrides the weak no-op in bare_glue.c; called from
 * ada_env_body before adainit so it precedes any raise. */
extern char __eh_frame_start[];
extern void __register_frame(void *fde);

void bare_register_eh_frames(void)
{
    __register_frame(__eh_frame_start);
}
