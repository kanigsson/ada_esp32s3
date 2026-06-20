--  Ada GDMA self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  ====================================================================
--  Exercises the reusable HAL DMA driver (ESP32S3.GDMA):
--    test1  a memory-to-memory copy of a 64-byte buffer, compared byte for byte;
--    test2  the controlled (RAII) Channel handle -- claim all five channels,
--           confirm a sixth claim is rejected, then (after the handles leave
--           scope, so Finalize releases them) confirm a fresh claim succeeds.
--
--  test2 is the point of the controlled handle: a Channel is non-copyable (two
--  tasks can't alias one) and auto-releases on scope exit, so channels can't
--  leak or be reused through a stale copy.  Report goes through the ROM printf
--  glue (the reliable console path here).
with Interfaces;   use Interfaces;
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.GDMA;  use ESP32S3.GDMA;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the test runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_gdma_banner");
   procedure Copy_Result (Ok : int);
   pragma Import (C, Copy_Result, "native_gdma_copy");
   procedure Raii_Result (Five, Sixth, Reclaimed, Ok : int);
   pragma Import (C, Raii_Result, "native_gdma_raii");
   procedure Done;
   pragma Import (C, Done, "native_gdma_done");

   type Buffer is array (0 .. 63) of Unsigned_8;
   Src : Buffer;
   Dst : Buffer := (others => 0);
begin
   delay until Clock + Milliseconds (200);
   Banner;

   for I in Buffer'Range loop
      Src (I) := Unsigned_8 ((I * 7 + 1) mod 256);
   end loop;

   --  test1: claim a channel, mem2mem copy, compare.
   declare
      C  : Channel;
      Ok : Boolean := False;
   begin
      Claim (C, Mem2Mem);
      if Is_Valid (C) then
         Copy (C, Dst'Address, Src'Address, Buffer'Length);
         Ok := (for all I in Buffer'Range => Dst (I) = Src (I));
      end if;
      Copy_Result (Boolean'Pos (Ok));
   end;                                   --  C finalizes -> channel released

   --  test2: exhaust the pool, confirm a sixth claim fails, then prove the
   --  channels are reclaimed once the handles go out of scope (Finalize).
   declare
      Five, Sixth_Rejected, Reclaimed : Boolean := False;
   begin
      declare
         C1, C2, C3, C4, C5, Extra : Channel;
      begin
         Claim (C1, Mem2Mem);  Claim (C2, Mem2Mem);  Claim (C3, Mem2Mem);
         Claim (C4, Mem2Mem);  Claim (C5, Mem2Mem);
         Five := Is_Valid (C1) and then Is_Valid (C2) and then Is_Valid (C3)
                   and then Is_Valid (C4) and then Is_Valid (C5);
         Claim (Extra, Mem2Mem);          --  no channel left
         Sixth_Rejected := not Is_Valid (Extra);
      end;                                --  Finalize C1..C5, Extra -> all freed

      declare
         C : Channel;
      begin
         Claim (C, Mem2Mem);              --  succeeds only if the five were freed
         Reclaimed := Is_Valid (C);
      end;

      Raii_Result (Boolean'Pos (Five), Boolean'Pos (Sixth_Rejected),
                   Boolean'Pos (Reclaimed),
                   Boolean'Pos (Five and Sixth_Rejected and Reclaimed));
   end;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
