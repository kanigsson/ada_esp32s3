/* IDF-free external-PSRAM region for esp32s3_psram (supplements the shared
 * memory.ld/sections.ld via an extra -T).  big.adb's 1 MB array lives in
 * .ext_ram.bss; bare_board_init (main/glue.c) brings up the octal PSRAM
 * (esp_psram_impl_enable) and maps PSRAM physical 0 -> this d-bus vaddr with the
 * ROM Cache_Dbus_MMU_Set, after which the array is backed by real PSRAM.
 * 0x3D000000 is a free, 64 KB-aligned slot in the cached external d-bus window
 * SOC_EXTRAM_DATA (0x3C000000..0x3E000000), clear of the flash rodata at 0x3C02xxxx. */
MEMORY
{
  ext_ram_seg (RW) : org = 0x3D000000, len = 0x200000     /* 2 MB window into PSRAM */
}

SECTIONS
{
  .ext_ram.bss (NOLOAD) :
  {
    . = ALIGN(16);
    _ext_ram_bss_start = ABSOLUTE(.);
    *(.ext_ram.bss .ext_ram.bss.*)
    . = ALIGN(16);
    _ext_ram_bss_end = ABSOLUTE(.);
  } > ext_ram_seg
}
