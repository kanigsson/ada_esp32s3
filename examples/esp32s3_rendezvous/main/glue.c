/* esp32s3_rendezvous: no example-specific natives (output via Ada.Text_IO).  The
   full RTS profile (task entries / accept / select / dynamic tasks) uses
   exceptions + finalization + a heap, supplied by ../../common/bare/{bare_heap,
   bare_libc}.c (build.sh sets HEAP_SIZE).  All bare-boot is shared in
   ../../common/bare/bare_glue.c, so this TU is empty. */
typedef int rendezvous_no_natives;   /* avoid an empty translation unit */
