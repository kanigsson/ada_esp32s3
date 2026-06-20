--  Ada PCNT self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  ===================================================================
--  Exercises the reusable HAL PCNT driver (ESP32S3.PCNT): a GPIO is software-
--  toggled a known number of times and that SAME pad is routed into a PCNT unit
--  (the matrix feeds the pad into the counter input -- no wiring); the counted
--  edges are compared to the number driven.  Also checks the controlled (RAII)
--  Unit handle.
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.PCNT;  use ESP32S3.PCNT;
with ESP32S3.GPIO;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_pcnt_banner");
   procedure Result (Pulses, Counted, Ok : int);
   pragma Import (C, Result, "native_pcnt_result");
   procedure Raii_Result (Four, Fifth, Reclaimed, Ok : int);
   pragma Import (C, Raii_Result, "native_pcnt_raii");
   procedure Done;
   pragma Import (C, Done, "native_pcnt_done");

   Pin    : constant ESP32S3.GPIO.Pin_Id := 4;   --  software-driven, PCNT-sensed
   Pulses : constant := 100;

   --  Hold each level a few microseconds so the glitch filter passes the edge.
   procedure Settle is
   begin
      delay until Clock + Microseconds (20);
   end Settle;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  Counting test: drive Pin low, then 100 clean high pulses, count the edges.
   declare
      U  : Unit;
      N  : Integer;
      Ok : Boolean;
   begin
      ESP32S3.GPIO.Configure (Pin, ESP32S3.GPIO.Output);
      ESP32S3.GPIO.Clear (Pin);
      Claim (U, 0);
      Configure (U, Pin => Pin);            --  count rising edges
      Settle;

      for I in 1 .. Pulses loop
         ESP32S3.GPIO.Set (Pin);   Settle;  --  rising edge -> +1
         ESP32S3.GPIO.Clear (Pin); Settle;
      end loop;

      N  := Count (U);
      Ok := (N = Pulses);
      Result (Pulses, int (N), Boolean'Pos (Ok));
   end;                                      --  U finalizes -> paused, released

   --  RAII: claim all 4 units, confirm a 5th fails, then reclaim on scope exit.
   declare
      Four, Fifth_Rejected, Reclaimed : Boolean := False;
   begin
      declare
         U0, U1, U2, U3, Extra : Unit;
      begin
         Claim (U0, 0); Claim (U1, 1); Claim (U2, 2); Claim (U3, 3);
         Four := Is_Valid (U0) and then Is_Valid (U1)
                   and then Is_Valid (U2) and then Is_Valid (U3);
         Claim (Extra, 0);
         Fifth_Rejected := not Is_Valid (Extra);
      end;

      declare
         U : Unit;
      begin
         Claim (U, 0);
         Reclaimed := Is_Valid (U);
      end;

      Raii_Result (Boolean'Pos (Four), Boolean'Pos (Fifth_Rejected),
                   Boolean'Pos (Reclaimed),
                   Boolean'Pos (Four and Fifth_Rejected and Reclaimed));
   end;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
