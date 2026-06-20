package Big is
   pragma Elaborate_Body;
   --  A 1 MB static byte array placed in external PSRAM (it would never fit in
   --  internal SRAM).  Run fills it with a pattern, reads it back, and reports
   --  its address + checksum so we can confirm it really lives in PSRAM and
   --  round-trips correctly.
   procedure Run;
end Big;
