--  Ada RTC-IO pad-hold self-test (ESP32-S3, no FreeRTOS, no IDF)
--  ===========================================================
--  Exercises the reusable HAL RTC-IO driver (ESP32S3.RTC_IO): an RTC-capable pad
--  is driven high and then HELD.  While held, a GPIO write to clear it is ignored
--  (the pad stays high); after Release, the same write takes effect (the pad goes
--  low).  The pad is read back with ESP32S3.GPIO.Read -- no wiring.
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.RTC_IO; use ESP32S3.RTC_IO;
with ESP32S3.GPIO;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_rtcio_banner");
   procedure Result (After_Set, While_Held, After_Release, Ok : int);
   pragma Import (C, Result, "native_rtcio_result");
   procedure Pull_Result (Pullup, Pulldown, Ok : int);
   pragma Import (C, Pull_Result, "native_rtcio_pull");
   procedure Done;
   pragma Import (C, Done, "native_rtcio_done");

   Pin      : constant ESP32S3.GPIO.Pin_Id := 5;  --  RTC-capable pad (hold test)
   Pull_Pin : constant ESP32S3.GPIO.Pin_Id := 6;  --  RTC-capable pad (pull test)

   function Read return Boolean is (ESP32S3.GPIO.Read (Pin));
begin
   delay until Clock + Milliseconds (200);
   Banner;

   ESP32S3.GPIO.Configure (Pin, ESP32S3.GPIO.Output);
   ESP32S3.GPIO.Set (Pin);                         --  drive high
   delay until Clock + Milliseconds (1);

   declare
      After_Set : constant Boolean := Read;        --  expect high

      Held_Level : Boolean;
      Released_Level : Boolean;
      Ok : Boolean;
   begin
      Hold (Pin);                                  --  latch it high
      ESP32S3.GPIO.Clear (Pin);                    --  try to drive low -- ignored
      delay until Clock + Milliseconds (1);
      Held_Level := Read;                          --  expect STILL high

      Release (Pin);                               --  unlatch
      ESP32S3.GPIO.Clear (Pin);                    --  now this takes effect
      delay until Clock + Milliseconds (1);
      Released_Level := Read;                       --  expect low

      --  PASS: high after set, still high while held despite the clear, low once
      --  released and cleared.
      Ok := After_Set and then Held_Level and then not Released_Level;
      Result (Boolean'Pos (After_Set), Boolean'Pos (Held_Level),
              Boolean'Pos (Released_Level), Boolean'Pos (Ok));
   end;

   --  RTC pull test: route a high-Z pad into the RTC domain, then watch it follow
   --  its RTC pull-up (high) and pull-down (low), read back with GPIO.Read.
   declare
      Up_Level, Down_Level : Boolean;
   begin
      ESP32S3.GPIO.Configure (Pull_Pin, ESP32S3.GPIO.Input);   --  high-Z input buffer on
      Enable_RTC_Input (Pull_Pin);                             --  connect the RTC pull

      Set_Pull (Pull_Pin, Up);
      delay until Clock + Milliseconds (5);
      Up_Level := ESP32S3.GPIO.Read (Pull_Pin);               --  expect high

      Set_Pull (Pull_Pin, Down);
      delay until Clock + Milliseconds (5);
      Down_Level := ESP32S3.GPIO.Read (Pull_Pin);             --  expect low

      Set_Pull (Pull_Pin, No_Pull);
      Pull_Result (Boolean'Pos (Up_Level), Boolean'Pos (Down_Level),
                   Boolean'Pos (Up_Level and then not Down_Level));
   end;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
