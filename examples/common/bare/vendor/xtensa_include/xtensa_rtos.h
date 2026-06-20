/* Minimal bare-metal replacement for ESP-IDF's xtensa_rtos.h.
 *
 * xtensa_context.S and xtensa_vectors.S #include xtensa_rtos.h, but the real IDF
 * header is the FreeRTOS-Xtensa port glue (drags in the FreeRTOS tick
 * xtensa_timer.h + config).  Those two .S files only need the Xtensa config
 * headers, the XT_STK_* frame layout (xtensa_context.h), and the XT_RTOS_* hook
 * macros -- so this shim provides exactly those, FreeRTOS-free.  It lets
 * bare_build.sh compile both from the vendored source instead of a prebuilt
 * .obj; each resulting object is instruction-for-instruction identical to IDF's.
 *
 * The hooks are just symbol NAMES -- the _frxt_* functions are resolved in the
 * link as before (the vector table merely calls them; the bare runtime drives
 * its own interrupts via highint5/L5, so these medium-level paths are inert).
 * XT_RTOS_TIMER_INT is deliberately NOT defined: the S3 ticks off the systimer,
 * not the Xtensa timer, so that path is config'd out (matching IDF's object). */
#include <xtensa/coreasm.h>
#include <xtensa/corebits.h>
#include <xtensa/config/system.h>
#include "xtensa_context.h"

#define XT_RTOS_INT_ENTER     _frxt_int_enter
#define XT_RTOS_INT_EXIT      _frxt_int_exit
#define XT_RTOS_CP_STATE      _frxt_task_coproc_state
#define XT_RTOS_CP_EXC_HOOK   _frxt_coproc_exc_hook
#define portNUM_PROCESSORS    2   /* ESP32-S3 is dual-core (was FreeRTOSConfig.h) */
