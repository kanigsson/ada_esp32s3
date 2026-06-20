--  Ada general-purpose timer self-test on the bare-metal ESP32-S3 (no IDF)
--  =======================================================================
--  Exercises the reusable HAL timer driver (ESP32S3.Timer): run TIMG0's timer at
--  1 MHz and cross-check its count against the runtime's own wall clock over a
--  fixed delay (the two independent time bases should agree), then verify a
--  one-shot alarm fires at the programmed count.  Also checks the controlled
--  (RAII) Timer handle.
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.Timer; use ESP32S3.Timer;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_timer_banner");
   procedure Count_Result (Expected, Measured, Ok : int);
   pragma Import (C, Count_Result, "native_timer_count");
   procedure Alarm_Result (Fired, Elapsed_Us, Ok : int);
   pragma Import (C, Alarm_Result, "native_timer_alarm");
   procedure Done;
   pragma Import (C, Done, "native_timer_done");
begin
   delay until Clock + Milliseconds (200);
   Banner;

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
         Count_Result (int (Expected), int (Measured), Boolean'Pos (Ok));
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
         Alarm_Result (Boolean'Pos (Fired), int (Us),
                       Boolean'Pos (Fired and then abs (Us - 30_000) <= 5_000));
         Clear_Alarm (T);
         Stop (T);
      end;
   end;                                  --  T finalizes -> stopped, released

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
