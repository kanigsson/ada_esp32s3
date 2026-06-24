--  Ada capacitive-touch read self-test (ESP32-S3, no FreeRTOS, no IDF)
--  =================================================================
--  Exercises the reusable HAL touch driver (ESP32S3.Touch): bring up the touch
--  FSM, scan two channels, and read their raw capacitance counts.  With nothing
--  connected, each pad still reads a stable non-zero baseline (its own
--  self-capacitance), and two different pads read different values -- which
--  proves the capacitance-measuring FSM is running on silicon.  Touch a pad and
--  its count rises.  No wiring needed for the baseline check.
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.Log;   use ESP32S3.Log;
with ESP32S3.Touch; use ESP32S3.Touch;
with ESP32S3.GPIO;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is

   --  "[touch] channel %d (GPIO%d): raw count = %d\n".
   procedure Chan (Ch, Gpio, Raw : Integer) is
   begin
      Put ("[touch] channel ");
      Put (Ch);
      Put (" (GPIO");
      Put (Gpio);
      Put ("): raw count = ");
      Put (Raw);
      New_Line;
   end Chan;

   --  "[touch] ch1: baseline=%d now=%d  Touched(baseline)=%d "
   --  "Touched(baseline+200k)=%d  %s\n" (the two Touched flags print as 0/1).
   procedure Thresh (Baseline, Now : Integer;
                     Untouched, Shifted, Ok : Boolean) is
   begin
      Put ("[touch] ch1: baseline=");
      Put (Baseline);
      Put (" now=");
      Put (Now);
      Put ("  Touched(baseline)=");
      Put (Boolean'Pos (Untouched));
      Put (" Touched(baseline+200k)=");
      Put (Boolean'Pos (Shifted));
      Put ("  ");
      Put_Line (if Ok then "PASS" else "FAIL");
   end Thresh;

   A : constant Channel := 1;     --  GPIO1
   B : constant Channel := 3;     --  GPIO3
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[touch] bare-metal capacitive-touch read self-test (no wiring)");

   Setup;
   Enable (A);
   Enable (B);
   delay until Clock + Milliseconds (50);     --  let the FSM scan a few rounds

   declare
      Ra : constant Natural := Read (A);
      Rb : constant Natural := Read (B);
      Ok : constant Boolean := Ra > 0 and then Rb > 0 and then Ra /= Rb;
   begin
      Chan (Integer (A), Natural (Pad (A)), Ra);
      Chan (Integer (B), Natural (Pad (B)), Rb);
      Put ("[touch] baseline counts non-zero + distinct: ");
      Put_Line (if Ok then "PASS" else "FAIL");
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
      Thresh (Baseline, Read (A), Untouched, Shifted, Ok);
   end;

   Put_Line ("[touch] done.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
