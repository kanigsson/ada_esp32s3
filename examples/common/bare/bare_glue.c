/* Shared IDF-free bare-boot glue for the bare ESP32-S3 examples.
 *
 * Our own 2nd-stage bootloader (../bootloader/, itself bare-metal) sets up the
 * flash-XIP cache/MMU and jumps to _start (../start.S), which selects the 240 MHz
 * PLL and calls start_c() (bare_boot.adb).  This glue then takes over so the
 * GNARL Ada runtime owns BOTH cores with FreeRTOS never running: core 0 runs the
 * env task; core 1 is cold-started into the GNARL slave scheduler.  There is no
 * esp_startup_start_app / idf.py -- start_c() calls app_main() directly.
 *
 * This file is shared by every bare example (compiled by bare_build.sh).  It
 * contains ONLY the bare-boot; each example provides its own tiny glue.c with the
 * C natives its Ada imports, and passes its Ada main symbol as -DADA_MAIN=_ada_<unit>
 * (the GNAT "_ada_<mainunit>" entry).  Default is _ada_main. */
#include <stdint.h>

#ifndef ADA_MAIN
#define ADA_MAIN _ada_main
#endif

/* From the ROM (rom_syms.ld) or bare_boot.adb -- not ESP-IDF. */
extern int  esp_rom_printf(const char *fmt, ...);
extern void esp_cpu_intr_enable(uint32_t mask);
extern void native_start_core1(void);          /* cold-start the APP_CPU      */
extern int  esp_clk_cpu_freq(void);

extern void adainit(void);
extern void adafinal(void) __attribute__((weak));  /* library-level finalization;
                                                weak: the configurable light-tasking
                                                binder (No_Finalization) emits none */
extern void __run_library_finalizers(void) __attribute__((weak));  /* synth'd (acats) */
extern void __gnat_start_slave_cpus(void);     /* GNARL Start_All_CPUs        */
extern void ADA_MAIN(void);                    /* the example's Ada main      */
extern void __gnat_esp32s3_core1_entry(void);  /* GNARL slave entry on core 1 */
extern volatile int gnat_hi5_marker;           /* force-link the L5 vector     */
extern void ets_set_appcpu_boot_addr(uint32_t addr);  /* ROM: APP_CPU entry    */
void app_main(void);                           /* core-0 bring-up              */
extern void __gnat_enter_env(void);            /* enter env task as outermost  */

/* Register the DWARF unwind frames for ZCX exceptions.  Weak no-op here (the
   light-tasking examples are No_Exception_Propagation); bare_libc.c provides the
   strong override that calls __register_frame for the embedded/full profiles. */
__attribute__((weak)) void bare_register_eh_frames(void) { }

/* Board-specific early init, run on core 0 before adainit while still
   single-threaded (core 1 is released later by __gnat_start_slave_cpus).  Weak
   no-op; esp32s3_psram overrides it to bring up + map the octal PSRAM. */
__attribute__((weak)) void bare_board_init(void) { }

/* The Ada environment task body: elaborate, release the slave CPUs, run the Ada
   main.  Entered as the OUTERMOST window frame via __gnat_enter_env (start.S,
   which references this symbol directly) so the first cooperative context switch
   does not corrupt a caller chain.  Non-static so the asm can name it.  Never
   returns. */
void ada_env_body(void)
{
    bare_board_init();              /* e.g. bring up + map external PSRAM         */
    bare_register_eh_frames();      /* register .eh_frame before any raise       */
    adainit();                      /* elaborate + activate tasks (core 0)      */
    __gnat_start_slave_cpus();      /* -> native_release_core1 -> core1_go = 1  */
    ADA_MAIN();                     /* the Ada main (the batch runner loops; a    */
                                    /* test-as-main RETURNS here)                */
    if (adafinal) adafinal();       /* program termination: await library tasks +
                                       the binder's finalization (RM 7.6.1).  Weak:
                                       absent under the light-tasking No_Finalization
                                       binder -> resolves to 0, call skipped         */
    /* gnatbind's configurable-run-time mode omits the finalize_library chain, so
       library-level controlled objects are NOT finalized by adafinal.  When the
       ACATS build merges a synthesized __run_library_finalizers into the image
       (build_acats_runner.sh), call it here so a program-main test whose grade is
       emitted from a library object's Finalize (e.g. C761001) actually finalizes.
       Weak: undefined for plain examples / wrapped batches -> resolves to 0. */
    if (__run_library_finalizers != 0) __run_library_finalizers();
    for (;;) { }
}

/* Environment-task stack (bounds imported by the runtime via __stack_*).  Size is
   set by bare_build.sh (-DENV_STACK_SIZE); the exception-capable embedded/full
   profiles want a larger one than the light-tasking default. */
#ifndef ENV_STACK_SIZE
#define ENV_STACK_SIZE 16384
#endif
#ifdef ENV_STACK_PSRAM
/* ENV_STACK_PSRAM: the env-task stack lives in a carved slice at the TOP of the
   bootloader-mapped PSRAM (bare_build.sh points __stack_start/__stack_end at it
   and shrinks the PSRAM heap to match) -- so recursion/elaboration-heavy tasks
   get a large primary stack without DRAM pressure.  No DRAM array is emitted. */
#else
char ada_env_stack[ENV_STACK_SIZE] __attribute__((aligned(16)));
#endif

/* Core 1's bring-up stack: core1_start (start.S) sets SP here before any C runs,
   so core 1 never spills onto core 0's stack.  Bounds via __core1_stack_end
   (bare_build.sh --defsym).  Used only until the GNARL slave switches to its idle
   stack. */
char core1_stack[8192] __attribute__((aligned(16)));
extern void core1_start(void);                 /* asm cold-entry for core 1   */

static volatile int      core1_go;       /* GNARL released core 1 (Start_All)  */
static volatile int      core1_alive;    /* core 1 reached its bare entry      */
static volatile int      sync_go;        /* core 0 published a fresh CCOUNT     */
static volatile uint32_t sync_ccount;
static volatile uint32_t saved_vecbase;  /* core 0 VECBASE, restored on core 1  */

/* CPU special-register access (PRID / CCOUNT / VECBASE rsr/wsr) lives in
   bare_boot.adb (System.Machine_Code asm).  The ONE exception is the core-1
   VECBASE *write* below: it must run before any windowed call -- to establish
   the exception vectors -- so it stays inline here as core1_bare_main's first
   act (a windowed call to set it could itself fault on a window overflow into
   an unset VECBASE). */
extern uint32_t native_get_ccount(void);    /* bare_boot.adb */
extern void     native_set_ccount(uint32_t c);
extern uint32_t native_get_vecbase(void);

static inline void set_vecbase(uint32_t v)
{
    asm volatile ("wsr.vecbase %0; rsync" :: "r"(v));
}

/* The cross-core poke (IPI) matrix wiring (native_setup_poke_core0/core1) is in
   bare_boot.adb as typed svd register access. */
void native_release_core1(void)      { core1_go = 1; }

/* --- board imports the runtime needs --- */
void     native_enable_tick(void)    { esp_cpu_intr_enable(1u << 16); }
void     native_enable_cpu_int(int n){ esp_cpu_intr_enable(1u << n); }
uint32_t native_cpu_freq_hz(void)    { return (uint32_t) esp_clk_cpu_freq(); }
void     native_freq_panic(uint32_t e, uint32_t a)
{
    esp_rom_printf("[C] FATAL: CPU %u Hz != runtime %u Hz\n",
                   (unsigned) a, (unsigned) e);
    for (;;) { }
}

/* Bare APP_CPU (core 1) entry -- the appcpu boot address after we reset core 1.
   Reached from the ROM in a C-callable state (as ESP-IDF's own call_start_cpu1
   is), so it can be an ordinary IRAM C function: no FreeRTOS task, no scheduler.
   Restore VECBASE (reset cleared it), align CCOUNT to core 0, wait for the GNARL
   release, then enter the slave scheduler (which switches to its own idle stack
   and never returns here). */
void __attribute__((section(".iram1.core1"))) core1_bare_main(void)
{
    set_vecbase(saved_vecbase);     /* reset cleared VECBASE; owns xt_highint5 */
    core1_alive = 1;                /* tell core 0 we are up                   */
    while (!sync_go) { }            /* wait for core 0 to publish a fresh CCOUNT*/
    asm volatile ("memw");
    native_set_ccount(sync_ccount + 32);  /* align to core 0 (240 MHz; tuned)  */
    while (!core1_go) { }           /* wait for GNARL Start_All_CPUs release    */
    __gnat_esp32s3_core1_entry();   /* enter slave scheduler; never returns    */
    for (;;) { }
}

#ifdef RECOVER_STACK_OVF
/* Recoverable stack overflow (full profile only -- needs ZCX + the GNARL
   __gnat_stack_overflow_raise, both absent on light-tasking/embedded).  The full
   runtime's s-taprop Enter_Task calls __gnat_arm_stack_watchpoint in the task's
   OWN context, so we arm a HW data-watchpoint a redzone above the running thread's
   stack limit: the first store that deepens into the redzone faults SYNCHRONOUSLY
   (a debug exception caught BEFORE the SP runs wild into the masked cache-error),
   with ~redzone bytes of real stack left to raise from.  stack_overflow.S's strong
   xt_debugexception override turns that fault into `raise Storage_Error`.

   No IDF here, so write the data-breakpoint SRs directly (data break #1): DBREAKA1
   = watched address, DBREAKC1 = StoreBreak (bit 31) | mask 0x3F (a 64-byte window).
   The 64-byte coverage cannot catch a single frame larger than 64 B that leaps
   over the window (e.g. ACATS CB1010A's 4000 B frames) -- an inherent limit. */
extern void __gnat_running_stack_bounds(void **low, void **high);
extern volatile int gnat_stack_ovf_marker;   /* force-link stack_overflow.S */

#define STACK_OVF_REDZONE 512

void __gnat_arm_stack_watchpoint(void)
{
    void *low = 0, *high = 0;
    __gnat_running_stack_bounds(&low, &high);
    if (low == 0) return;                       /* no running thread / unknown */
    uint32_t addr = ((uint32_t) (uintptr_t) low + STACK_OVF_REDZONE) & ~63u;
    uint32_t dbc  = 0x80000000u | 0x3fu;        /* StoreBreakEn(bit31) + 64-byte mask */
    asm volatile ("wsr.dbreaka1 %0\n\t"
                  "wsr.dbreakc1 %1\n\t"
                  "dsync" :: "r"(addr), "r"(dbc));
}
#endif

/* app_main is called directly by start_c() (bare_boot.adb, reached from start.S)
   in the IDF-free build -- there is no esp_startup_start_app to wrap.  Never
   returns. */
void app_main(void)
{
    gnat_hi5_marker = 1;
#ifdef RECOVER_STACK_OVF
    gnat_stack_ovf_marker = 1;   /* force-link the xt_debugexception override */
#endif
    esp_rom_printf("\n[C] Ada runtime up on both cores\n");

    saved_vecbase = native_get_vecbase();  /* core 0's VECBASE (== _vector_table) */

    /* Start core 1 from cold: point the APP_CPU at our bare entry, then un-gate
       its clock + pulse its reset (the IDF-free bootloader never started it). */
    ets_set_appcpu_boot_addr((uint32_t) core1_start);
    native_start_core1();

    while (!core1_alive) { }        /* core 1 reached core1_bare_main           */
    sync_ccount = native_get_ccount();  /* fresh core-0 CCOUNT for alignment    */
    asm volatile ("memw");
    sync_go = 1;                    /* release core 1's CCOUNT alignment        */

    /* Enter the Ada runtime as the OUTERMOST register-window frame (see
       __gnat_enter_env in start.S).  __gnat_enter_env discards the
       app_main/start_c/_start caller frames (never returned to) and tail-jumps
       into ada_env_body, which becomes the top frame -- like the runtime's own
       task entry -- so the first cooperative context switch cannot corrupt a
       caller chain. */
    __gnat_enter_env();
    for (;;) { }                    /* unreachable */
}
