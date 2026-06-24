--  Ada SDM self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  ==================================================================
--  Exercises the reusable HAL SDM driver (ESP32S3.SDM): set a sigma-delta channel
--  to several output densities and measure each back by GPIO-sampling the output
--  pad's average (high samples / total) over a window -- NO wiring.  A sigma-delta
--  stream's average equals its programmed density, so the sampled fraction should
--  track the set value.  Also checks the controlled (RAII) Channel handle.
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SDM;   use ESP32S3.SDM;
with ESP32S3.GPIO;
with ESP32S3.Log;   use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   Pin : constant ESP32S3.GPIO.Pin_Id := 4;     --  SDM output, GPIO-sampled

   Densities : constant array (1 .. 3) of Density_Percent := (25.0, 50.0, 75.0);

   --  Average the output pad over Window_Ms -> high fraction as a percentage.
   function Measure (Window_Ms : Positive) return Float is
      Deadline : constant Time := Clock + Milliseconds (Window_Ms);
      Samples, Highs : Natural := 0;
   begin
      loop
         Samples := Samples + 1;
         if ESP32S3.GPIO.Read (Pin) then
            Highs := Highs + 1;
         end if;
         exit when Clock >= Deadline;
      end loop;
      return Float (Highs) / Float (Samples) * 100.0;
   end Measure;

   M  : Float;
   Ok : Boolean;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[sdm] bare-metal SDM sigma-delta density self-test "
             & "(GPIO-sampled, no wiring)");

   declare
      Ch : Channel;
   begin
      Claim (Ch, 0);
      --  A low carrier frequency slows the pulse stream so the GPIO sampler
      --  oversamples each bit and averages fairly (a fast 50 %-density square would
      --  otherwise alias against the fixed sample loop).
      Configure (Ch, Pin => Pin, Carrier_Hz => 400_000);
      for I in Densities'Range loop
         Set_Density (Ch, Densities (I));
         delay until Clock + Milliseconds (5);
         M  := Measure (50);
         Ok := abs (M - Float (Densities (I))) <= 6.0;     --  within 6 %
         Put ("[sdm] density set=");
         Put (Integer (Float (Densities (I))));
         Put ("%   measured=");
         Put_Fixed (Integer (M * 10.0), 10, 1);
         Put ("%   ");
         Put_Line (if Ok then "PASS" else "FAIL");
      end loop;
   end;                                  --  Ch finalizes -> output low, released

   --  RAII: claim all 8 channels, confirm a 9th fails, reclaim on scope exit.
   declare
      Eight, Ninth_Rejected, Reclaimed : Boolean := False;
   begin
      declare
         C0, C1, C2, C3, C4, C5, C6, C7, Extra : Channel;
      begin
         Claim (C0, 0); Claim (C1, 1); Claim (C2, 2); Claim (C3, 3);
         Claim (C4, 4); Claim (C5, 5); Claim (C6, 6); Claim (C7, 7);
         Eight := Is_Valid (C0) and then Is_Valid (C7);
         Claim (Extra, 0);
         Ninth_Rejected := not Is_Valid (Extra);
      end;

      declare
         C : Channel;
      begin
         Claim (C, 0);
         Reclaimed := Is_Valid (C);
      end;

      Put ("[sdm] raii: 8-claimed=");
      Put (if Eight then "y" else "n");
      Put (" 9th-rejected=");
      Put (if Ninth_Rejected then "y" else "n");
      Put (" reclaimed=");
      Put (if Reclaimed then "y" else "n");
      Put ("  ");
      Put_Line (if Eight and Ninth_Rejected and Reclaimed then "PASS" else "FAIL");
   end;

   Put_Line ("[sdm] done.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
