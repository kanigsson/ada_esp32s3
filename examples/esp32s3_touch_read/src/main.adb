--  Ada capacitive-touch read self-test (ESP32-S3, no FreeRTOS, no IDF)
--  =================================================================
--  Exercises the reusable HAL touch driver (ESP32S3.Touch): bring up the touch
--  FSM, scan two channels, and read their raw capacitance counts.  With nothing
--  connected, each pad still reads a stable non-zero baseline (its own
--  self-capacitance), and two different pads read different values -- which
--  proves the capacitance-measuring FSM is running on silicon.  Touch a pad and
--  its count rises.  No wiring needed for the baseline check.
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.Touch; use ESP32S3.Touch;
with ESP32S3.GPIO;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_touch_banner");
   procedure Chan (Ch, Gpio, Raw : int);
   pragma Import (C, Chan, "native_touch_chan");
   procedure Result (Ok : int);
   pragma Import (C, Result, "native_touch_result");
   procedure Thresh (Raw, Bench, Touched_Hi, Touched_Lo, Ok : int);
   pragma Import (C, Thresh, "native_touch_thresh");
   procedure Done;
   pragma Import (C, Done, "native_touch_done");

   A : constant Channel := 1;     --  GPIO1
   B : constant Channel := 3;     --  GPIO3
begin
   delay until Clock + Milliseconds (200);
   Banner;

   Setup;
   Enable (A);
   Enable (B);
   delay until Clock + Milliseconds (50);     --  let the FSM scan a few rounds

   declare
      Ra : constant Natural := Read (A);
      Rb : constant Natural := Read (B);
      Ok : constant Boolean := Ra > 0 and then Rb > 0 and then Ra /= Rb;
   begin
      Chan (int (A), int (Natural (Pad (A))), int (Ra));
      Chan (int (B), int (Natural (Pad (B))), int (Rb));
      Result (Boolean'Pos (Ok));
   end;

   --  Touch-detection test: capture the untouched baseline, then check the
   --  threshold logic.  Against the real baseline the pad reads "not touched";
   --  against a deliberately-shifted reference it reads "touched" -- proving the
   --  margin comparison.  (A finger raises the real count past the margin.)
   declare
      Baseline   : constant Natural := Read (A);
      Untouched  : constant Boolean := Touched (A, Baseline, Margin => 50_000);
      Shifted    : constant Boolean := Touched (A, Baseline + 200_000, Margin => 50_000);
      Ok         : constant Boolean := not Untouched and then Shifted;
   begin
      Thresh (int (Baseline), int (Read (A)), Boolean'Pos (Untouched),
              Boolean'Pos (Shifted), Boolean'Pos (Ok));
   end;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
