/* Minimal IDF esp_attr.h shim: only the IRAM/DRAM section attrs xtensa_intr.c
   uses (its xt_unhandled_interrupt goes in IRAM).  Matches IDF's .iram1.<n>. */
#pragma once
#define _CTR2(c) #c
#define _CTR1(c) _CTR2(c)
#define IRAM_ATTR __attribute__((section(".iram1." _CTR1(__COUNTER__))))
#define DRAM_ATTR __attribute__((section(".dram1." _CTR1(__COUNTER__))))
