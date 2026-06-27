/* esp32s3_intr_levels: L2/L3/L5 interrupt-vector regression test native glue.
   Shared bare-boot (core bring-up, env entry, L5 tick) is in
   ../../common/bare/bare_glue.c. */
#include <stdint.h>
extern int esp_rom_printf(const char *fmt, ...);

void ada_log(int n) { esp_rom_printf("[intr] %d\n", n); }

/* Fire the L2 and L3 device-interrupt vectors with no external wiring, via the
   FROM_CPU interrupt-matrix sources (same mechanism as the cross-core poke):
   route FROM_CPU_0 -> CPU_INT 19 (Device_L2_0, level 2) and FROM_CPU_1 ->
   CPU_INT 23 (Device_L3_0, level 3); assert by writing the SYSTEM FROM_CPU
   register, and the attached Ada handler clears it.  (L5 = the always-firing
   tick; L4 has no vector on this port -- EXCSAVE_4 is scratch for L5.) */
#define REG(a) (*(volatile uint32_t *) (uintptr_t) (a))
#define INTR_CORE0_FROM_CPU0_MAP 0x600C213Cu   /* maps source -> CPU int (5b) */
#define INTR_CORE0_FROM_CPU1_MAP 0x600C2140u
#define SYS_FROM_CPU0            0x600C0030u    /* assert = 1 / clear = 0 */
#define SYS_FROM_CPU1            0x600C0034u

void ada_setup_l2l3(void)
{
    REG(INTR_CORE0_FROM_CPU0_MAP) = 19;        /* FROM_CPU_0 -> L2 (CPU_INT 19) */
    REG(INTR_CORE0_FROM_CPU1_MAP) = 23;        /* FROM_CPU_1 -> L3 (CPU_INT 23) */
    /* CPU ints 19/23 are enabled when the Ada handlers attach. */
}
void ada_fire_l2(void)  { REG(SYS_FROM_CPU0) = 1; }
void ada_fire_l3(void)  { REG(SYS_FROM_CPU1) = 1; }
void ada_clear_l2(void) { REG(SYS_FROM_CPU0) = 0; }
void ada_clear_l3(void) { REG(SYS_FROM_CPU1) = 0; }

/* THREADPTR accessors -- the victim's per-task-TLS corruption check. */
unsigned int ada_get_tp(void)
{ unsigned int v; __asm__ volatile ("rur.threadptr %0" : "=r"(v)); return v; }
void ada_set_tp(unsigned int v)
{ __asm__ volatile ("wur.threadptr %0" : : "r"(v)); }
