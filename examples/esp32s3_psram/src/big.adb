pragma Warnings (Off);
with Interfaces;               use Interfaces;
with System.Storage_Elements;  use System.Storage_Elements;

package body Big is

   Size : constant := 1024 * 1024;   --  1 MB

   --  Placed in the external-RAM bss section (mapped to PSRAM by ESP-IDF when
   --  CONFIG_SPIRAM_ALLOW_BSS_SEG_EXTERNAL_MEMORY is set).
   Buffer : array (0 .. Size - 1) of Unsigned_8
     with Linker_Section => ".ext_ram.bss";

   procedure Report (Addr, Bytes, Checksum : Unsigned_32);
   pragma Import (C, Report, "native_buf_report");

   procedure Run is
      Sum : Unsigned_32 := 0;
   begin
      --  Write a pattern across the whole 1 MB...
      for I in Buffer'Range loop
         Buffer (I) := Unsigned_8 (I mod 256);
      end loop;
      --  ...then read it all back and checksum it (proves the round trip).
      for I in Buffer'Range loop
         Sum := Sum + Unsigned_32 (Buffer (I));
      end loop;
      Report (Unsigned_32 (To_Integer (Buffer'Address)),
              Buffer'Length, Sum);
   end Run;

end Big;
