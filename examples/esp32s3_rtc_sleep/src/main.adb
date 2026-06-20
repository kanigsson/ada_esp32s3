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
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.RTC;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;
   pragma Import (C, Banner, "native_rtc_banner");
   procedure Boot (Cause, Count : int);
   pragma Import (C, Boot, "native_rtc_boot");
   procedure Sleeping (Ms : int);
   pragma Import (C, Sleeping, "native_rtc_sleeping");
   procedure Final (Count, Cause, Ok : int);
   pragma Import (C, Final, "native_rtc_final");

   use ESP32S3.RTC;
   WC : constant Wake_Cause := Last_Wake;

   --  The boot counter, kept in retained RTC slow memory (word 0) via the
   --  driver's Read/Write accessors.
   Boot_Count : Unsigned_32 := Read (0);
begin
   delay until Clock + Milliseconds (200);
   Banner;
   Disable_Super_Watchdog;     --  a deep-sleep wake can leave it armed

   --  A deep-sleep wake continues the count; anything else (power-on / a flash
   --  reset) starts fresh at 1.
   if WC = Deep_Sleep_Timer or else WC = Deep_Sleep_GPIO then
      Boot_Count := Boot_Count + 1;
   else
      Boot_Count := 1;
   end if;
   Write (0, Boot_Count);                          --  persist it

   Boot (int (Wake_Cause'Pos (WC)), int (Boot_Count));

   if Boot_Count < 4 then
      --  Sleep ~2 s and wake via the RTC timer; this does not return on success.
      Sleeping (2000);
      delay until Clock + Milliseconds (50);     --  let the console flush
      Deep_Sleep_For (2.0);
      --  Only reached if the sleep was rejected -- report the cause and stop.
      loop
         Final (-1, int (Raw_Reject_Cause), 0);  --  -1 boot count = "sleep rejected"
         delay until Clock + Seconds (2);
      end loop;
   end if;

   --  Reached only after several wake cycles: stay awake and report the result
   --  (counter advanced past 1, and the last wake was a deep-sleep timer wake).
   loop
      Final (int (Boot_Count), int (Wake_Cause'Pos (WC)),
             Boolean'Pos (Boot_Count >= 4 and then WC = Deep_Sleep_Timer));
      delay until Clock + Seconds (2);
   end loop;
end Main;
