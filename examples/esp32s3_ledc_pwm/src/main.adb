--  Ada LEDC PWM self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  =======================================================================
--  Drives PWM through the reusable HAL (ESP32S3.LEDC) and measures it back with
--  NO external wiring: the channel's output pad is sampled with ESP32S3.GPIO.Read
--  in a tight loop over a timed window (high samples / total = duty, rising edges
--  / elapsed = frequency).  Also checks the controlled (RAII) Channel handle.
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.LEDC;  use ESP32S3.LEDC;
with ESP32S3.GPIO;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the test runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_ledc_banner");
   procedure Result (Set_Pct, Meas_Pct_X10, Meas_Hz, Ok : int);
   pragma Import (C, Result, "native_ledc_result");
   procedure Raii_Result (Eight, Ninth, Reclaimed, Ok : int);
   pragma Import (C, Raii_Result, "native_ledc_raii");
   procedure Done;
   pragma Import (C, Done, "native_ledc_done");

   Pin0 : constant ESP32S3.GPIO.Pin_Id := 4;     --  channel 0 output (sampled)
   Freq : constant := 5_000;

   Duties : constant array (1 .. 2) of Duty_Percent := (25.0, 75.0);

   --  Sample the (driver-driven) output pad for Window_Ms; return the high-sample
   --  fraction as a duty %, and rising-edges / elapsed-time as a frequency.
   procedure Measure (Pin : ESP32S3.GPIO.Pin_Id; Window_Ms : Positive;
                      Duty_Pct, Freq_Hz : out Float)
   is
      T0       : constant Time := Clock;
      Deadline : constant Time := T0 + Milliseconds (Window_Ms);
      Samples, Highs, Rising : Natural := 0;
      Cur  : Boolean;
      Prev : Boolean := False;
      Secs : Float;
   begin
      loop
         Cur := ESP32S3.GPIO.Read (Pin);
         Samples := Samples + 1;
         if Cur then
            Highs := Highs + 1;
            if not Prev then
               Rising := Rising + 1;
            end if;
         end if;
         Prev := Cur;
         exit when Clock >= Deadline;
      end loop;
      Secs := Float (To_Duration (Clock - T0));
      Duty_Pct := (if Samples = 0 then 0.0
                   else Float (Highs) / Float (Samples) * 100.0);
      Freq_Hz  := (if Secs = 0.0 then 0.0 else Float (Rising) / Secs);
   end Measure;

   D, F : Float;
   Ok   : Boolean;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   --  PWM test on channel 0 at 5 kHz, 10-bit, sampled at 25 % and 75 %.
   declare
      Ch0 : Channel;
   begin
      Claim (Ch0, 0);
      Configure (Ch0, Freq => Freq, Pin => Pin0, Bits => 10);
      for I in Duties'Range loop
         Set_Duty (Ch0, Duties (I));
         delay until Clock + Milliseconds (5);
         Measure (Pin0, 50, D, F);
         Ok := abs (D - Float (Duties (I))) <= 4.0
                 and then abs (F - Float (Freq)) <= Float (Freq) * 0.10;
         Result (int (Float (Duties (I))), int (D * 10.0), int (F),
                 Boolean'Pos (Ok));
      end loop;
   end;                                  --  Ch0 finalizes -> output stopped, freed

   --  RAII: claim all 8, confirm a 9th fails, then prove reclamation on scope exit.
   declare
      Eight, Ninth_Rejected, Reclaimed : Boolean := False;
   begin
      declare
         C0, C1, C2, C3, C4, C5, C6, C7, Extra : Channel;
      begin
         Claim (C0, 0); Claim (C1, 1); Claim (C2, 2); Claim (C3, 3);
         Claim (C4, 4); Claim (C5, 5); Claim (C6, 6); Claim (C7, 7);
         Eight := Is_Valid (C0) and then Is_Valid (C7);
         Claim (Extra, 0);              --  channel 0 already taken
         Ninth_Rejected := not Is_Valid (Extra);
      end;                              --  all finalize -> freed

      declare
         C : Channel;
      begin
         Claim (C, 0);
         Reclaimed := Is_Valid (C);
      end;

      Raii_Result (Boolean'Pos (Eight), Boolean'Pos (Ninth_Rejected),
                   Boolean'Pos (Reclaimed),
                   Boolean'Pos (Eight and Ninth_Rejected and Reclaimed));
   end;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
