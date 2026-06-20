/* Minimal sdkconfig.h shim: the one CONFIG_* that changes the from-source xtensa
   objects vs IDF -- the interrupt-backtrace s32e blocks in xtensa_vectors.S. */
#pragma once
#define CONFIG_FREERTOS_INTERRUPT_BACKTRACE 1
