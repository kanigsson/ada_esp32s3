--  Ada SAR ADC self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  ======================================================================
--  Exercises the reusable HAL ADC driver (ESP32S3.ADC): ADC1 channel 0 is wired
--  to GPIO1.  We drive that pad HIGH with the GPIO output driver and read the
--  ADC (expect near full scale), then drive it LOW and read again (expect near
--  zero).  The pad is both driven and ADC-sensed, so no wiring is needed.
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.ADC;  use ESP32S3.ADC;
with ESP32S3.GPIO;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_adc_banner");
   procedure Result (High_Code, Low_Code, Ok : int);
   pragma Import (C, Result, "native_adc_result");
   procedure Dbg (Cal_Code, Done : int);
   pragma Import (C, Dbg, "native_adc_dbg");
   procedure Done;
   pragma Import (C, Done, "native_adc_done");

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
   Banner;

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
      Result (int (High), int (Low), Boolean'Pos (Ok));
      Dbg (int (Cal_Code (ADC1)), Boolean'Pos (Last_Done));
   end;                                  --  R finalizes -> unit released

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
