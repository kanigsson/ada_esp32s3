/* Minimal FreeRTOS.h shim: xtensa_intr.c includes it ONLY for portNUM_PROCESSORS
   and xPortGetCoreID (per its own comment) -- no FreeRTOS code.  xPortGetCoreID
   inlines (via esp_cpu/xt_utils in IDF) to a PRID-bit-13 read; reproduce that. */
#pragma once
#define portNUM_PROCESSORS 2
static inline __attribute__((pure)) int xPortGetCoreID(void)
{   unsigned id; __asm__ volatile ("rsr.prid %0\n extui %0,%0,13,1" : "=r"(id)); return (int) id; }
