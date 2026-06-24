--  Ada SAR ADC self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  ======================================================================
--  Exercises the reusable HAL ADC driver (ESP32S3.ADC): ADC1 channel 0 is wired
--  to GPIO1.  We drive that pad HIGH with the GPIO output driver and read the
--  ADC (expect near full scale), then drive it LOW and read again (expect near
--  zero).  The pad is both driven and ADC-sensed, so no wiring is needed.
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.ADC;  use ESP32S3.ADC;
with ESP32S3.GPIO;
with ESP32S3.Log;  use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   Ch  : constant Channel_Index := 0;            --  ADC1 ch0 -> GPIO1
   Pin : constant ESP32S3.GPIO.Pin_Id := Channel_Pin (ADC1, Ch);

   --  Median of a few reads (cheap noise rejection).
   function Sample (R : Reader) return Natural is
      A : constant Natural := Read (R, Ch);
      B : constant Natural := Read (R, Ch);
      C : constant Natural := Read (R, Ch);
   begin
      return (A + B + C) / 3;
   end Sample;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[adc] bare-metal SAR ADC one-shot self-test (drive+sense one pad, no wiring)");

   declare
      R : Reader;
      High, Low : Natural := 0;
      Ok : Boolean;
   begin
      Claim (R, ADC1);

      --  Drive the pad high, settle, read.
      ESP32S3.GPIO.Configure (Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Set (Pin);
      delay until Clock + Milliseconds (2);
      High := Sample (R);

      --  Drive the pad low, settle, read.
      ESP32S3.GPIO.Clear (Pin);
      delay until Clock + Milliseconds (2);
      Low := Sample (R);

      --  Clear separation: high near full scale, low near zero.
      Ok := High > 3000 and then Low < 500 and then High > Low;
      Put ("[adc] ADC1 ch0: drive-high=");
      Put (High);
      Put ("  drive-low=");
      Put (Low);
      Put ("  ");
      Put_Line (if Ok then "PASS" else "FAIL");
      Put ("[adc]   cal_code=");
      Put (Cal_Code (ADC1));
      Put ("  last_done=");
      Put (Boolean'Pos (Last_Done));
      New_Line;
   end;                                  --  R finalizes -> unit released

   Put_Line ("[adc] done.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
