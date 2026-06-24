--  Ada RTC deep-sleep + retained-memory self-test (ESP32-S3, no FreeRTOS, no IDF)
--  ============================================================================
--  Exercises the reusable HAL RTC driver (ESP32S3.RTC): a boot counter lives in
--  retained RTC slow memory, which survives deep sleep (the digital core powers
--  down and the chip resets on wake).  Each boot we read the wake cause, bump the
--  counter, and -- for the first few boots -- deep-sleep with a timer wake.  The
--  counter persisting across the resets, and the wake cause turning into
--  "deep-sleep-timer", proves retained memory + deep sleep + timer wake.  After a
--  few cycles the board stays awake and repeats the final state so it can be
--  captured cleanly (the USB-JTAG console drops during each sleep).
with Interfaces;   use Interfaces;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.RTC;
with ESP32S3.Log;  use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   --  Wake-cause name, matching the C cause_name() mapping by Wake_Cause'Pos.
   function Cause_Name (C : Integer) return String is
     (case C is
         when 0      => "power-on",
         when 1      => "deep-sleep-timer",
         when 2      => "deep-sleep-gpio",
         when others => "other-reset");

   use ESP32S3.RTC;
   WC : constant Wake_Cause := Last_Wake;

   --  The boot counter, kept in retained RTC slow memory (word 0) via the
   --  driver's Read/Write accessors.
   Boot_Count : Unsigned_32 := Read (0);
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[rtc] bare-metal RTC deep-sleep + retained-memory self-test");
   Disable_Super_Watchdog;     --  a deep-sleep wake can leave it armed

   --  A deep-sleep wake continues the count; anything else (power-on / a flash
   --  reset) starts fresh at 1.
   if WC = Deep_Sleep_Timer or else WC = Deep_Sleep_GPIO then
      Boot_Count := Boot_Count + 1;
   else
      Boot_Count := 1;
   end if;
   Write (0, Boot_Count);                          --  persist it

   Put ("[rtc] boot: wake=");
   Put (Cause_Name (Wake_Cause'Pos (WC)));
   Put ("  retained boot-count=");
   Put (Integer (Boot_Count));
   New_Line;

   if Boot_Count < 4 then
      --  Sleep ~2 s and wake via the RTC timer; this does not return on success.
      Put_Line ("[rtc] entering deep sleep for ~2000 ms "
                & "(console drops until wake)...");
      delay until Clock + Milliseconds (50);     --  let the console flush
      Deep_Sleep_For (2.0);
      --  Only reached if the sleep was rejected -- report the cause and stop.
      loop
         --  -1 boot count = "sleep rejected"
         Put ("[rtc] FINAL: boot-count=");
         Put (-1);
         Put ("  last-wake=");
         Put (Cause_Name (Integer (Raw_Reject_Cause)));
         Put ("  ");
         Put_Line ("FAIL");
         delay until Clock + Seconds (2);
      end loop;
   end if;

   --  Reached only after several wake cycles: stay awake and report the result
   --  (counter advanced past 1, and the last wake was a deep-sleep timer wake).
   loop
      Put ("[rtc] FINAL: boot-count=");
      Put (Integer (Boot_Count));
      Put ("  last-wake=");
      Put (Cause_Name (Wake_Cause'Pos (WC)));
      Put ("  ");
      Put_Line (if Boot_Count >= 4 and then WC = Deep_Sleep_Timer
                then "PASS" else "FAIL");
      delay until Clock + Seconds (2);
   end loop;
end Main;
