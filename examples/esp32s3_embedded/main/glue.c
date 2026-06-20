/* esp32s3_embedded: no example-specific natives.  The demo's output goes
   through Ada.Text_IO (handled by the runtime), and the embedded RTS profile's
   heap + freestanding libc come from ../../common/bare/{bare_heap,bare_libc}.c
   (build.sh sets HEAP_SIZE).  All bare-boot is shared in ../../common/bare/
   bare_glue.c, so this translation unit is empty. */
typedef int embedded_no_natives;   /* avoid an empty translation unit */
