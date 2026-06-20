------------------------------------------------------------------------------
--  SDK DEFAULT board configuration -- NOT a global config every project shares.
--
--  Each project owns its own config/board.ads (bare_build reads THAT, and errors
--  if it's missing).  This file is the SDK baseline, used only for:
--    * the scaffold template -- `esp32-ada init` / `./x new` copy it;
--    * the prebuilt default bootloader (reused by projects whose PSRAM_Size
--      matches; a project with a different PSRAM_Size gets its own bootloader);
--    * the host tools' compiled-in fallback (elf2image / esp_flash `with Board;`
--      -- bare_build/bare_flash always override it with the project's size).
--  (PSRAM_Size is what the bootloader maps at boot; Flash_Size only sizes the
--  image header / SPI params.)
------------------------------------------------------------------------------
package Board is

   --  Total SPI flash size.  A "hint" the ROM/bootloader read at runtime; the
   --  real chip size is auto-detected.  Used by elf2image (image header) and
   --  esp_flash (SPI_SET_PARAMS default).
   Flash_Size : constant := 2 * 1024 * 1024;     --  2 MB

   --  External PSRAM size MAPPED at 0x3D000000 by the 2nd-stage bootloader.
   --  Must be a multiple of the 64 KB MMU page and <= the physical chip.
   PSRAM_Size : constant := 2 * 1024 * 1024;     --  2 MB

end Board;
