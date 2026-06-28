------------------------------------------------------------------------------
--  Board configuration for THIS project -- flash + external PSRAM size.
--
--  Each project owns this file; bare_build reads it to size the image header and
--  to build/select the 2nd-stage bootloader.  The SIMD benchmark keeps its
--  vectors in internal SRAM (no PSRAM needed), so PSRAM_Size is the SDK default.
------------------------------------------------------------------------------
package Board is

   Flash_Size : constant := 2 * 1024 * 1024;     --  2 MB

   PSRAM_Size : constant := 2 * 1024 * 1024;     --  2 MB

end Board;
