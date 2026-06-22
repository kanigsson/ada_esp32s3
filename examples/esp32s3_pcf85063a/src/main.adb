--  PCF85063A real-time-clock driver demo on the bare-metal ESP32-S3 (no
--  FreeRTOS, no IDF).  Exercises the reusable HAL RTC driver (ESP32S3.PCF85063A)
--  against a real PCF85063A on the I2C bus:
--
--     SDA = IO8     SCL = IO7     (no INT line wired -- see Rtc_Int below)
--
--  What it does, end to end on silicon:
--    probe      address the chip (Get_Time): ACK => present, NACK => absent.
--    reset      software-reset to a known register state.
--    set-time   load a known calendar (writing seconds clears the OS flag, so
--               the clock-integrity flag reads OK afterwards).
--    set-alarm  arm a seconds-match alarm 5 s out (enables the INT output too).
--    watch      print the time once a second; when the alarm flag (AF) latches,
--               report it and acknowledge it (which releases INT).
--
--  The wiring is stated here (Rtc_Sda / Rtc_Scl / Rtc_Int) and handed to Setup;
--  the driver hard-codes no pins.  This board has no PCF85063A INT connection,
--  so Rtc_Int is No_Pin and the alarm is found by polling AF over I2C.  Point
--  Rtc_Int at the GPIO the INT line is wired to (active-low, open-drain) to arm
--  the hardware interrupt instead -- the falling-edge ISR then latches
--  Alarm_IRQ.Fired.
--
--  Report goes through the ROM printf glue (the reliable console path here); the
--  Ada driver does all the I2C/register work.
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.GPIO;
with ESP32S3.PCF85063A;
with ESP32S3.PCF85063A.Interrupts;
with Alarm_IRQ;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the demo runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package RTC renames ESP32S3.PCF85063A;
   use type RTC.Status;

   --  Board wiring for THIS example (the driver hard-codes none).  The
   --  PCF85063A on this board has no INT line, so its pin is No_Pin and the
   --  alarm is found by polling AF over I2C.  Point it at a real GPIO (and the
   --  Attach below arms the hardware interrupt) if INT is wired.
   Rtc_Sda : constant ESP32S3.GPIO.Pin_Id      := 8;
   Rtc_Scl : constant ESP32S3.GPIO.Pin_Id      := 7;
   Rtc_Int : constant ESP32S3.GPIO.Optional_Pin := ESP32S3.GPIO.No_Pin;

   procedure Banner;            pragma Import (C, Banner,    "native_rtc_banner");
   procedure Step (Code, Ok : int);
                                pragma Import (C, Step,      "native_rtc_step");
   procedure No_Device;         pragma Import (C, No_Device, "native_rtc_no_device");
   procedure Show (Year, Mon, Day, Wday, Hh, Mm, Ss, Valid : int);
                                pragma Import (C, Show,      "native_rtc_time");
   procedure Alarm (By_Int : int);
                                pragma Import (C, Alarm,     "native_rtc_alarm");
   procedure Done;              pragma Import (C, Done,      "native_rtc_done");

   Dev   : RTC.Device;
   T     : RTC.Time;
   Valid : Boolean;
   St    : RTC.Status;

   --  2026-06-22 is a Monday.
   Initial : constant RTC.Time :=
     (Year   => 2026, Month  => 6, Day    => 22, Day_Of_Week => RTC.Monday,
      Hour   => 14,   Minute => 30, Second => 0);

   procedure Print (When_T : RTC.Time; Integrity : Boolean) is
   begin
      Show (Year  => int (When_T.Year),
            Mon   => int (When_T.Month),
            Day   => int (When_T.Day),
            Wday  => int (RTC.Weekday'Pos (When_T.Day_Of_Week)),
            Hh    => int (When_T.Hour),
            Mm    => int (When_T.Minute),
            Ss    => int (When_T.Second),
            Valid => Boolean'Pos (Integrity));
   end Print;

begin
   delay until Clock + Milliseconds (200);   --  let the console settle
   Banner;

   --  State the wiring; the device remembers it.  Attach arms the INT interrupt
   --  on the stored pin -- a no-op here since Rtc_Int is No_Pin.
   RTC.Setup (Dev, Sda => Rtc_Sda, Scl => Rtc_Scl, Int_Pin => Rtc_Int);
   RTC.Interrupts.Attach (Dev, Alarm_IRQ.Handler'Access);

   --  probe: does the chip ACK its address?
   RTC.Get_Time (Dev, T, Valid, St);
   Step (0, Boolean'Pos (St = RTC.OK));
   if St /= RTC.OK then
      No_Device;
      loop
         delay until Clock + Seconds (3600);
      end loop;
   end if;

   --  reset -> set-time -> read back.
   RTC.Reset (Dev, St);
   Step (1, Boolean'Pos (St = RTC.OK));

   RTC.Set_Time (Dev, Initial, St);
   Step (2, Boolean'Pos (St = RTC.OK));

   RTC.Get_Time (Dev, T, Valid, St);
   if St = RTC.OK then
      Print (T, Valid);
   end if;

   --  arm a seconds-match alarm 5 s out (the time was just set to :00).
   RTC.Set_Alarm
     (Dev, (Use_Second => True, Second => 5, others => <>), St);
   Step (3, Boolean'Pos (St = RTC.OK));

   --  watch the clock tick; stop when the alarm flag latches.
   for Tick in 1 .. 10 loop
      delay until Clock + Seconds (1);

      RTC.Get_Time (Dev, T, Valid, St);
      if St = RTC.OK then
         Print (T, Valid);
      end if;

      declare
         Fired : Boolean;
      begin
         RTC.Alarm_Triggered (Dev, Fired, St);   --  read AF over I2C
         if St = RTC.OK and then Fired then
            --  Report how it was detected: the INT ISR latched the flag (a pin
            --  was wired and fired) or the I2C poll above found it.
            Alarm (Boolean'Pos (Alarm_IRQ.Fired));
            RTC.Acknowledge_Alarm (Dev, St);          --  release INT
            exit;
         end if;
      end;
   end loop;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
