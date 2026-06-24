--  Ada general-purpose timer self-test on the bare-metal ESP32-S3 (no IDF)
--  =======================================================================
--  Exercises the reusable HAL timer driver (ESP32S3.Timer): run TIMG0's timer at
--  1 MHz and cross-check its count against the runtime's own wall clock over a
--  fixed delay (the two independent time bases should agree), then verify a
--  one-shot alarm fires at the programmed count.  Also checks the controlled
--  (RAII) Timer handle.
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.Log;   use ESP32S3.Log;
with ESP32S3.Timer; use ESP32S3.Timer;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is

   --  "[timer] 1 MHz count over 50 ms: expected~%d measured=%d  %s\n".
   procedure Count_Result (Expected, Measured : Integer; Ok : Boolean) is
   begin
      Put ("[timer] 1 MHz count over 50 ms: expected~");
      Put (Expected);
      Put (" measured=");
      Put (Measured);
      Put ("  ");
      Put_Line (if Ok then "PASS" else "FAIL");
   end Count_Result;

   --  "[timer] alarm@30000: fired=%d at~%d us  %s\n" (fired printed as 0/1).
   procedure Alarm_Result (Fired : Boolean; Elapsed_Us : Integer; Ok : Boolean)
   is
   begin
      Put ("[timer] alarm@30000: fired=");
      Put (Boolean'Pos (Fired));
      Put (" at~");
      Put (Elapsed_Us);
      Put (" us  ");
      Put_Line (if Ok then "PASS" else "FAIL");
   end Alarm_Result;

begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[timer] bare-metal general-purpose timer self-test");

   declare
      T : Timer;
   begin
      Claim (T, 0);
      Configure (T, Tick_Hz => 1_000_000);    --  1 tick = 1 us

      --  Count test: run for 50 ms of runtime time, expect ~50000 ticks.
      Reset (T);
      Start (T);
      delay until Clock + Milliseconds (50);
      declare
         Measured : constant Ticks := Value (T);
         Expected : constant := 50_000;
         Ok : constant Boolean :=
           abs (Integer (Measured) - Expected) <= Expected / 50;   --  within 2 %
      begin
         Count_Result (Expected, Integer (Measured), Ok);
      end;
      Stop (T);

      --  Alarm test: reset, alarm at 30000 ticks (30 ms), run and wait for it.
      Reset (T);
      Set_Alarm (T, 30_000);
      declare
         T0    : constant Time := Clock;
         Guard : Natural := 50_000_000;
         Fired : Boolean := False;
         Us    : Integer;
      begin
         Start (T);
         while not Fired and then Guard > 0 loop
            Fired := Alarm_Fired (T);
            Guard := Guard - 1;
         end loop;
         Us := Integer (To_Duration (Clock - T0) * 1_000_000.0);
         --  Should fire near 30 ms (30000 us); allow generous slack for the
         --  polling loop and clock granularity.
         Alarm_Result (Fired, Us,
                       Fired and then abs (Us - 30_000) <= 5_000);
         Clear_Alarm (T);
         Stop (T);
      end;
   end;                                  --  T finalizes -> stopped, released

   Put_Line ("[timer] done.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
