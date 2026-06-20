pragma Warnings (Off);
with Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;
with Blink;
pragma Unreferenced (Blink);

--  Minimal program built against the pinned esp32s3_rts: the
--  environment task logs a 1 Hz heartbeat counter; package Blink runs a 100 ms
--  library-level task.  Both use `delay until` (the native CCOMPARE2 tick), so
--  a steady heartbeat on the console confirms the crate runtime boots + the
--  scheduler runs on hardware.
procedure Example is
   procedure Log (Marker : Interfaces.C.int);
   pragma Import (C, Log, "ada_log");
   use type Interfaces.C.int;
   Count : Interfaces.C.int := 0;
   Next  : Time := Clock + Seconds (1);
begin
   loop
      delay until Next;
      Count := Count + 1;
      Log (Count);
      Next := Next + Seconds (1);
   end loop;
end Example;
