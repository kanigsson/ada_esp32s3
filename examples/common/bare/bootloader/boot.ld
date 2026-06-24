/* IDF-free minimal 2nd-stage bootloader -- RAM layout.
 *
 * The 1st-stage mask ROM loads this image (from flash 0x0) into SRAM and jumps to
 * the entry (_start).  We mirror the IDF bootloader's high-SRAM placement so we do
 * not collide with the ROM's load-time stack, and so the loader code sits ABOVE
 * the app's RAM (the app's dram0_0_seg ends at 0x3FCDB700 = IRAM 0x403CB700) --
 * that way copying the app's segments can never overwrite the running loader.
 * Addresses transcribed from ESP-IDF v5.4.4 bootloader.ld (esp32s3). */

iram_dram_offset = 0x6f0000;                 /* SRAM1 DIRAM IRAM<->DRAM alias delta */
usable_dram_end  = 0x3fce9700;
stack_overhead   = 0x2000;                   /* startup stack lives above dram_seg  */
dram_seg_len     = 0x5000;
iram_seg_len     = 0x7000;
dram_seg_end     = usable_dram_end - stack_overhead;
dram_seg_start   = dram_seg_end - dram_seg_len;
iram_seg_start   = dram_seg_start - iram_seg_len + iram_dram_offset;   /* -> 0x403CB700 */

MEMORY
{
  iram_seg (RWX) : org = iram_seg_start, len = iram_seg_len
  dram_seg (RW)  : org = dram_seg_start, len = dram_seg_len
}

ENTRY(_start);
_stack_top = usable_dram_end;                /* SP starts here, grows down          */

SECTIONS
{
  .text :
  {
    _text_start = ABSOLUTE(.);
    *(.literal .literal.* .text .text.*)
    _text_end = ABSOLUTE(.);
  } > iram_seg

  .rodata :
  {
    *(.rodata .rodata.* .srodata .srodata.* .sdata2 .sdata2.*)
    . = ALIGN(4);
  } > dram_seg

  .data :
  {
    . = ALIGN(4);
    *(.data .data.* .sdata .sdata.*)
    . = ALIGN(4);
  } > dram_seg

  .bss (NOLOAD) :
  {
    . = ALIGN(4);
    _bss_start = ABSOLUTE(.);
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    _bss_end = ABSOLUTE(.);
  } > dram_seg
}
