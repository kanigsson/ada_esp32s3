--  Ada RMT self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  ==================================================================
--  Exercises the reusable HAL RMT driver (ESP32S3.RMT): a TX channel transmits a
--  burst of {level, duration} symbols on a GPIO pad; an RX channel reads that
--  SAME pad back (the matrix loops the pad's output into the RX input -- no
--  wiring) and captures the burst; the received durations are compared to what
--  was sent.  This verifies both the TX and RX paths plus the tick divider.
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.RMT;   use ESP32S3.RMT;
with ESP32S3.GPIO;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_rmt_banner");
   procedure Result (Sent, Received, Ok : int);
   pragma Import (C, Result, "native_rmt_result");
   procedure Dump (I, L0, D0, L1, D1 : int);
   pragma Import (C, Dump, "native_rmt_dump");
   procedure Done;
   pragma Import (C, Done, "native_rmt_done");

   Pad : constant ESP32S3.GPIO.Pin_Id := 4;     --  TX drives it, RX reads it back
   Res : constant := 1_000_000;                 --  1 MHz -> 1 tick = 1 us

   --  Four distinctive symbols (high then low, microsecond durations).
   Sent : constant Symbol_Array :=
     ((Level0 => True, Duration0 =>  50, Level1 => False, Duration1 =>  60),
      (Level0 => True, Duration0 =>  80, Level1 => False, Duration1 =>  90),
      (Level0 => True, Duration0 => 120, Level1 => False, Duration1 => 130),
      (Level0 => True, Duration0 => 160, Level1 => False, Duration1 => 170));

   Got   : Symbol_Array (0 .. 15);
   Count : Natural;

   --  A received duration matches a sent one within +/- Tol ticks.
   Tol : constant := 4;
   function Near (A, B : Tick_Count) return Boolean is
     (abs (Integer (A) - Integer (B)) <= Tol);
begin
   delay until Clock + Milliseconds (200);
   Banner;

   declare
      Tx : TX_Channel;
      Rx : RX_Channel;
      Ok : Boolean := False;
   begin
      Claim (Tx, 0);
      Claim (Rx, 0);
      Configure (Tx, Resolution_Hz => Res, Pin => Pad);
      Configure (Rx, Resolution_Hz => Res, Pin => Pad, Idle_Ticks => 1_000);

      Start (Rx);                              --  arm the receiver first
      Transmit (Tx, Sent);                     --  drive the burst onto the pad
      Receive (Rx, Got, Count);                --  block until idle, read it back

      --  Every high pulse and every low pulse should round-trip, except the very
      --  last low -- the idle period that ends reception truncates it (standard
      --  RMT behaviour: the last symbol comes back with Duration1 = 0).
      Ok := Count = Sent'Length;
      if Ok then
         for I in Sent'Range loop
            Ok := Ok and then Near (Got (I).Duration0, Sent (I).Duration0);
            if I < Sent'Last then
               Ok := Ok and then Near (Got (I).Duration1, Sent (I).Duration1);
            end if;
         end loop;
      end if;

      Result (Sent'Length, int (Count), Boolean'Pos (Ok));
      for I in 0 .. Natural'Min (Count, 8) - 1 loop
         Dump (int (I), Boolean'Pos (Got (I).Level0), int (Got (I).Duration0),
               Boolean'Pos (Got (I).Level1), int (Got (I).Duration1));
      end loop;
   end;                                        --  Tx, Rx finalize -> released

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
