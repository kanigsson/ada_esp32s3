/* Minimal heap for the IDF-free embedded/full RTS profiles.  Those profiles use
 * `new` + finalization, so GNAT's System.Memory needs malloc/free/realloc/calloc.
 * The Alire toolchain's newlib is big-endian (unusable here) and we have no
 * libc, so provide a tiny first-fit free-list allocator.  Blocks are kept in
 * address order (split forward, never reordered) so a single forward sweep
 * coalesces perfectly.  A global INTLEVEL-15 critical section serialises it
 * (env task + finalizers).
 *
 * The arena is the LEFTOVER DRAM -- [_heap_low_start, _bare_heap_top) from
 * sections.ld -- not a fixed .bss array, so it claims all RAM after .data/.bss/
 * stacks (the full profile's task stacks come from here too).  Only compiled/
 * linked when an example's build.sh sets HEAP_SIZE (the light-tasking examples
 * never allocate, so they omit it). */
#include <stdint.h>
#include <stddef.h>

extern uint8_t _heap_low_start[];   /* free DRAM start (after .data/.bss/stacks) */
extern uint8_t _bare_heap_top[];    /* top of dram0_0_seg                        */

/* HEAP_PSRAM: put the arena in the external PSRAM the 2nd-stage bootloader maps
 * at 0x3D000000 (HEAP_PSRAM_SIZE bytes, = BOARD_PSRAM_SIZE) instead of the small
 * leftover DRAM.  The DRAM heap is only ~256 KB, which OOMs the multi-task /
 * large-alloc ACATS tests (CXD8002, CXD4007, CXD4009, C433Axx, ...); PSRAM gives
 * them MBs.  Task-body trampolines use a SEPARATE SRAM1-exec allocator (glue.c),
 * so the non-executable d-bus PSRAM here is fine for stacks / `new` / sec-stacks. */
#ifndef HEAP_PSRAM_BASE
#define HEAP_PSRAM_BASE 0x3D000000u
#endif

typedef struct hdr {
    size_t      size;    /* payload bytes (excl. header), 16-aligned */
    struct hdr *next;    /* next block by ascending address          */
    int         used;
} hdr_t;

#define HDR_SZ (((sizeof(hdr_t)) + 15u) & ~(size_t)15u)

static hdr_t *heap_head;

static uint32_t enter_crit(void)
{ uint32_t ps; __asm__ volatile ("rsil %0, 15" : "=r"(ps)); return ps; }
static void leave_crit(uint32_t ps)
{ __asm__ volatile ("wsr.ps %0; rsync" :: "r"(ps)); }

static void heap_init(void)
{
#ifdef HEAP_PSRAM
    uintptr_t base = ((uintptr_t) HEAP_PSRAM_BASE + 15u) & ~(uintptr_t)15u;
    uintptr_t top  =  ((uintptr_t) HEAP_PSRAM_BASE + (uintptr_t) HEAP_PSRAM_SIZE)
                      & ~(uintptr_t)15u;
#else
    uintptr_t base = ((uintptr_t) _heap_low_start + 15u) & ~(uintptr_t)15u;
    uintptr_t top  =  (uintptr_t) _bare_heap_top    & ~(uintptr_t)15u;
#endif
    heap_head = (hdr_t *) base;
    heap_head->size = (size_t)(top - base) - HDR_SZ;
    heap_head->next = NULL;
    heap_head->used = 0;
}

void *malloc(size_t n)
{
    if (n == 0) return NULL;
    n = (n + 15u) & ~(size_t)15u;
    uint32_t ps = enter_crit();
    if (!heap_head) heap_init();
    for (hdr_t *b = heap_head; b; b = b->next) {
        if (!b->used && b->size >= n) {
            if (b->size >= n + HDR_SZ + 16u) {           /* split off a remainder */
                hdr_t *nb = (hdr_t *)((uint8_t *)b + HDR_SZ + n);
                nb->size = b->size - n - HDR_SZ;
                nb->next = b->next;
                nb->used = 0;
                b->size = n;
                b->next = nb;
            }
            b->used = 1;
            leave_crit(ps);
            return (uint8_t *)b + HDR_SZ;
        }
    }
    leave_crit(ps);
    {   /* DEBUG (CXD4009 heap-exhaustion hypothesis): report OOM so we can see
           whether a task-stack/sec-stack alloc fails during activation. */
        extern int esp_rom_printf(const char *fmt, ...);
        esp_rom_printf("[heap] out of memory: %u bytes requested\n", (unsigned) n);
    }
    return NULL;                                          /* out of memory */
}

void free(void *p)
{
    if (!p) return;
    hdr_t *b = (hdr_t *)((uint8_t *)p - HDR_SZ);
    uint32_t ps = enter_crit();
    b->used = 0;
    for (hdr_t *c = heap_head; c; c = c->next)            /* full forward coalesce */
        while (c->next && !c->used && !c->next->used)
            { c->size += HDR_SZ + c->next->size; c->next = c->next->next; }
    leave_crit(ps);
}

void *realloc(void *p, size_t n)
{
    if (!p) return malloc(n);
    if (n == 0) { free(p); return NULL; }
    hdr_t *b = (hdr_t *)((uint8_t *)p - HDR_SZ);
    if (b->size >= ((n + 15u) & ~(size_t)15u)) return p;  /* fits in place */
    void *np = malloc(n);
    if (np) {
        uint8_t *s = p, *d = np;
        for (size_t i = 0; i < b->size; i++) d[i] = s[i];
        free(p);
    }
    return np;
}

void *calloc(size_t a, size_t b)
{
    size_t n = a * b;
    void *p = malloc(n);
    if (p) { uint8_t *d = p; for (size_t i = 0; i < n; i++) d[i] = 0; }
    return p;
}

/* Per-task primary-stack reclamation hook, called by the full RTS's
 * System.Task_Primitives.Operations.Finalize_TCB (Stack_Free_Hook =
 * __gnat_task_stack_free) when a task that OWNS its heap-allocated stack
 * terminates.  Without this symbol the hook is weak/undefined and Finalize_TCB
 * SKIPS the free -> every terminated task leaks its primary stack, so a
 * multi-task ACATS batch progressively exhausts the heap (OOM -> a fresh task
 * gets a null stack -> wild jump).  Defining it stops the leak.
 *
 * Reaping race: the GNARL can wake a dying task's master (which runs
 * Finalize_TCB) before the task has Slept off its own stack, so a cross-core
 * free here could pull the stack out from under a task still executing on it
 * (use-after-free).  Spin until the thread is no longer the running thread on
 * either core, THEN free; bounded so we leak-on-timeout and NEVER UAF. */
extern void *__gnat_running_thread_table[2];   /* per-core running BB thread */
void __gnat_task_stack_free(void *stack, void *thread);
void __gnat_task_stack_free(void *stack, void *thread)
{
    for (unsigned i = 0; i < 2000000u; i++) {
        if (__gnat_running_thread_table[0] != thread &&
            __gnat_running_thread_table[1] != thread) {
            free(stack);
            return;
        }
    }
    /* timed out (thread stuck running?) -- leak rather than risk a UAF */
}
