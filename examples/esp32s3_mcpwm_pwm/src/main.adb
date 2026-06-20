--  Ada MCPWM PWM-output self-test on the bare-metal ESP32-S3 (no FreeRTOS, no IDF)
--  =============================================================================
--  Drives edge-aligned PWM through the reusable HAL (ESP32S3.MCPWM) and measures
--  it back with NO external wiring: the generator's output pad is sampled with
--  ESP32S3.GPIO.Read in a tight loop over a timed window.  Counting high samples
--  gives the duty cycle (a clock-independent ratio); counting rising edges over
--  the measured elapsed time gives the frequency.
--
--  A generator channel and a capture channel are claimed as limited, controlled
--  RAII handles (Channel / Capture) -- non-copyable and auto-released on scope
--  exit -- so this also exercises the ownership model.
--
--  20 kHz on GPIO4, checked at 25 % and 75 % duty.  A "PASS" (measured duty and
--  frequency within tolerance) confirms real PWM on silicon.  Report goes
--  through the ROM printf glue (the reliable console path here).
with Interfaces;   use Interfaces;
with Interfaces.C;  use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.MCPWM;
with ESP32S3.GPIO;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the test runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   use ESP32S3.MCPWM;

   procedure Banner;
   pragma Import (C, Banner, "native_mcpwm_banner");
   procedure Result (Set_Pct, Meas_Pct_X10, Meas_Hz, Ok : int);
   pragma Import (C, Result, "native_mcpwm_result");
   procedure Pair (Duty_A_X10, Duty_B_X10, Overlap_X10, Ok : int);
   pragma Import (C, Pair, "native_mcpwm_pair");
   procedure Cap_Result (Freq_Hz, Duty_X10, Ok : int);
   pragma Import (C, Cap_Result, "native_mcpwm_capture");
   procedure Fault_Result (Run_Pct, Fault_Pct, Resume_Pct, Ok : int);
   pragma Import (C, Fault_Result, "native_mcpwm_fault");
   procedure Carrier_Result (Off_Pct, On_Pct, Ok : int);
   pragma Import (C, Carrier_Result, "native_mcpwm_carrier");
   procedure Done;
   pragma Import (C, Done, "native_mcpwm_done");

   Out_Pin : constant ESP32S3.GPIO.Pin_Id := 4;
   Freq    : constant := 20_000;

   --  Complementary-pair test pins (A, B) on channel 1.
   Pair_A : constant ESP32S3.GPIO.Pin_Id := 6;
   Pair_B : constant ESP32S3.GPIO.Pin_Id := 7;

   Fault_Pin   : constant ESP32S3.GPIO.Pin_Id := 8;   --  driven by us as the fault
   Carrier_Pin : constant ESP32S3.GPIO.Pin_Id := 9;   --  channel-2 carrier output

   Duties : constant array (1 .. 2) of Duty_Percent := (25.0, 75.0);

   --  Claimed channel handles (declared up front so the nested helpers below can
   --  see the capture handle).  Each is released automatically when Main returns.
   Gen0 : Channel;     --  channel 0 -> Out_Pin (duty + capture + fault tests)
   Gen1 : Channel;     --  channel 1 -> complementary pair
   Gen2 : Channel;     --  channel 2 -> carrier test
   Cap  : Capture;     --  capture channel 0 -> Out_Pin

   --  Sample the (driver-driven) output pad for Window_Ms; return the high-sample
   --  fraction as a duty %, and rising-edges / elapsed-time as a frequency.
   procedure Measure (Window_Ms : Positive; Duty_Pct, Freq_Hz : out Float) is
      T0      : constant Time := Clock;
      Deadline : constant Time := T0 + Milliseconds (Window_Ms);
      Samples, Highs, Rising : Natural := 0;
      Cur  : Boolean;
      Prev : Boolean := False;
      Secs : Float;
   begin
      loop
         Cur := ESP32S3.GPIO.Read (Out_Pin);
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

   --  Sample a complementary pair: per-pad duty and the fraction of time BOTH
   --  pads are high (which the dead-time should keep at ~0).
   procedure Measure_Pair (Window_Ms : Positive;
                           Duty_A, Duty_B, Overlap : out Float)
   is
      Deadline : constant Time := Clock + Milliseconds (Window_Ms);
      Samples, Highs_A, Highs_B, Both : Natural := 0;
      A, B : Boolean;
   begin
      loop
         A := ESP32S3.GPIO.Read (Pair_A);
         B := ESP32S3.GPIO.Read (Pair_B);
         Samples := Samples + 1;
         if A then Highs_A := Highs_A + 1; end if;
         if B then Highs_B := Highs_B + 1; end if;
         if A and B then Both := Both + 1; end if;
         exit when Clock >= Deadline;
      end loop;
      Duty_A  := Float (Highs_A) / Float (Samples) * 100.0;
      Duty_B  := Float (Highs_B) / Float (Samples) * 100.0;
      Overlap := Float (Both)    / Float (Samples) * 100.0;
   end Measure_Pair;

   --  High fraction of any (driven) output pad over a window.
   function Duty_Of (Pin : ESP32S3.GPIO.Pin_Id; Window_Ms : Positive) return Float is
      Deadline : constant Time := Clock + Milliseconds (Window_Ms);
      Samples, Highs : Natural := 0;
   begin
      loop
         Samples := Samples + 1;
         if ESP32S3.GPIO.Read (Pin) then Highs := Highs + 1; end if;
         exit when Clock >= Deadline;
      end loop;
      return Float (Highs) / Float (Samples) * 100.0;
   end Duty_Of;

   --  Measure Out_Pin precisely with the capture submodule: ticks (80 MHz) for
   --  one full period (rising->rising) and the high time (rising->falling).
   procedure Capture_Measure (Period, High : out Natural) is
      V : Unsigned_32; Falling : Boolean;
      R0, Fall, R1 : Unsigned_32 := 0;
      Got_R0, Got_F, Got_R1 : Boolean := False;
      Guard : Natural := 5_000_000;
   begin
      while Capture_Pending (Cap) loop               --  drain stale captures
         Read_Capture (Cap, V, Falling);
      end loop;
      loop
         if Capture_Pending (Cap) then
            Read_Capture (Cap, V, Falling);
            if not Got_R0 and then not Falling then
               R0 := V; Got_R0 := True;
            elsif Got_R0 and then not Got_F and then Falling then
               Fall := V; Got_F := True;
            elsif Got_F and then not Got_R1 and then not Falling then
               R1 := V; Got_R1 := True;
            end if;
         end if;
         exit when Got_R1 or else Guard = 0;
         Guard := Guard - 1;
      end loop;
      Period := Natural (R1 - R0);     --  modular subtraction handles a wrap
      High   := Natural (Fall - R0);
   end Capture_Measure;

   D, F          : Float;
   Da, Db, Ov    : Float;
   Ok            : Boolean;
begin
   delay until Clock + Milliseconds (200);
   Banner;

   Setup (MCPWM0);
   Claim (Gen0, MCPWM0, Ch0);
   Configure_Channel (Gen0, Freq => Freq, Pin => Out_Pin);
   Start (Gen0);

   for I in Duties'Range loop
      Set_Duty (Gen0, Duties (I));
      delay until Clock + Milliseconds (5);     --  let the new duty latch
      Measure (50, D, F);

      Ok := abs (D - Float (Duties (I))) <= 4.0       --  duty within 4 %
              and then abs (F - Float (Freq)) <= Float (Freq) * 0.10;  --  freq within 10 %

      Result (int (Float (Duties (I))), int (D * 10.0), int (F),
              Boolean'Pos (Ok));
   end loop;

   --  Complementary pair + dead-time on channel 1: A on Pair_A, inverted B on
   --  Pair_B, with 1 us of dead-time, at 50 % duty.  Expect A and B each ~50 %
   --  (minus the dead-time gap) and ~0 % overlap -- the dead-time guarantees the
   --  two are never high together.
   Claim (Gen1, MCPWM0, Ch1);
   Configure_Channel (Gen1, Freq => Freq, Pin => Pair_A,
                      Complement_Pin => Pair_B, Dead_Time_Ns => 1_000);
   Start (Gen1);
   Set_Duty (Gen1, 50.0);
   delay until Clock + Milliseconds (5);
   Measure_Pair (50, Da, Db, Ov);
   Ok := abs (Da - 50.0) <= 6.0       --  A ~ 50 % (less the dead-time gap)
           and then abs (Db - 50.0) <= 6.0   --  B ~ 50 % (complementary)
           and then Ov < 1.0;                --  never both high (dead-time)
   Pair (int (Da * 10.0), int (Db * 10.0), int (Ov * 10.0), Boolean'Pos (Ok));

   ----------------------------------------------------------------------------
   --  Test 3: CAPTURE -- feed channel 0's own output (Out_Pin) into capture 0
   --  on the same pad and measure period + high precisely (80 MHz timer).
   ----------------------------------------------------------------------------
   Set_Duty (Gen0, 30.0);
   Claim (Cap, MCPWM0, Cap0);
   Configure_Capture (Cap, Pin => Out_Pin, Edge => Both_Edges);
   delay until Clock + Milliseconds (5);
   declare
      Period, High : Natural;
      CF, CD : Float;
   begin
      Capture_Measure (Period, High);
      CF := (if Period = 0 then 0.0 else Float (Capture_Clock_Hz) / Float (Period));
      CD := (if Period = 0 then 0.0 else Float (High) / Float (Period) * 100.0);
      Ok := abs (CF - Float (Freq)) <= Float (Freq) * 0.05
              and then abs (CD - 30.0) <= 3.0;
      Cap_Result (int (CF), int (CD * 10.0), Boolean'Pos (Ok));
   end;

   ----------------------------------------------------------------------------
   --  Test 4: FAULT -- drive Fault_Pin and trip channel 0 (force low, one-shot).
   --  Running ~50 %, forced ~0 % while asserted, ~50 % again after Clear_Fault.
   ----------------------------------------------------------------------------
   ESP32S3.GPIO.Configure (Fault_Pin, ESP32S3.GPIO.Output);
   ESP32S3.GPIO.Clear (Fault_Pin);                       --  inactive (no fault)
   Configure_Fault (MCPWM0, Fault0, Pin => Fault_Pin, Active_High => True);
   Protect_Channel (Gen0, Fault0, One_Shot, Force_Low);
   Set_Duty (Gen0, 50.0);
   delay until Clock + Milliseconds (2);
   declare
      Run, Trip, Resume : Float;
   begin
      Run := Duty_Of (Out_Pin, 20);
      ESP32S3.GPIO.Set (Fault_Pin);                      --  assert the fault
      delay until Clock + Milliseconds (2);
      Trip := Duty_Of (Out_Pin, 20);
      ESP32S3.GPIO.Clear (Fault_Pin);                    --  deassert ...
      Clear_Fault (Gen0);                                --  ... and release the latch
      delay until Clock + Milliseconds (2);
      Resume := Duty_Of (Out_Pin, 20);
      Ok := abs (Run - 50.0) <= 6.0 and then Trip < 2.0
              and then abs (Resume - 50.0) <= 6.0;
      Fault_Result (int (Run), int (Trip), int (Resume), Boolean'Pos (Ok));
   end;

   ----------------------------------------------------------------------------
   --  Test 5: CARRIER -- channel 2 at 100 % duty: constant high with the carrier
   --  off, chopped to the carrier's own duty (~50 %) with it on.
   ----------------------------------------------------------------------------
   Claim (Gen2, MCPWM0, Ch2);
   Configure_Channel (Gen2, Freq => Freq, Pin => Carrier_Pin);
   Start (Gen2);
   Set_Duty (Gen2, 100.0);
   delay until Clock + Milliseconds (2);
   declare
      Off, On : Float;
   begin
      Off := Duty_Of (Carrier_Pin, 20);                  --  ~100 %
      Set_Carrier (Gen2, Enable => True,
                   Prescale => 15, Duty_Eighths => 4, First_Pulse => 0);
      delay until Clock + Milliseconds (2);
      On := Duty_Of (Carrier_Pin, 20);                   --  chopped -> ~50 %
      Ok := Off > 95.0 and then On in 30.0 .. 70.0;
      Carrier_Result (int (Off), int (On), Boolean'Pos (Ok));
   end;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
