/* esp32s3_full_tasking: no example-specific natives (output via Ada.Text_IO).
   The full RTS profile (rendezvous/select/abort/dynamic tasks) uses exceptions +
   finalization + a heap, supplied by ../../common/bare/{bare_heap,bare_libc}.c
   (build.sh sets HEAP_SIZE).  We deliberately do NOT define __gnat_task_stack_alloc,
   so each task's primary stack comes from the internal Ada heap (bare_heap) rather
   than PSRAM -- the IDF-free build does not bring up the octal SPIRAM, and main.adb's
   In_PSRAM check degrades cleanly (just skips the "stack is in PSRAM" line).  All
   bare-boot is shared in ../../common/bare/bare_glue.c, so this TU is empty. */
typedef int full_tasking_no_natives;   /* avoid an empty translation unit */
