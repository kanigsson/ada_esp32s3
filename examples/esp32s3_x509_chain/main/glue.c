/* esp32s3_x509_chain: example-specific C natives go here.  The shared bare-boot (bringing
   the GNARL runtime up on both cores) lives in ../../common/bare/bare_glue.c,
   so a new project can leave this file empty.  Add the C functions your Ada
   imports (a print helper over esp_rom_printf, peripheral pokes, ...) here. */
typedef int esp32s3_x509_chain_no_natives;   /* avoid an empty translation unit */
