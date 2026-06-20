------------------------------------------------------------------------------
--  GNAT RUN-TIME COMPONENTS (ESP32-S3 full)
--  S Y S T E M . O S _ P R I M I T I V E S
--  B o d y
------------------------------------------------------------------------------

with System.BB.Time;
with System.BB.Parameters;

package body System.OS_Primitives is

   use type System.BB.Time.Time;

   Freq : constant System.BB.Time.Time :=
     System.BB.Time.Time (System.BB.Parameters.Clock_Frequency);

   -----------------
   -- Initialize  --
   -----------------

   procedure Initialize is
   begin
      null;
   end Initialize;

   -----------
   -- Clock --
   -----------

   function Clock return Duration is
      Ticks : constant System.BB.Time.Time := System.BB.Time.Clock;
      Whole : constant System.BB.Time.Time := Ticks / Freq;
      Frac  : constant System.BB.Time.Time := Ticks mod Freq;
   begin
      --  Integer-only conversion (avoids soft-float): whole seconds plus the
      --  fractional remainder Frac/Freq of a second.
      return Duration (Whole) + Duration (Frac) / Integer (Freq);
   end Clock;

   ----------------
   -- Timed_Delay --
   ----------------

   procedure Timed_Delay (Time : Duration; Mode : Integer) is
      Deadline : constant Duration :=
        (if Mode = Relative then Clock + Time else Time);
   begin
      --  Fallback busy-wait; tasking delays use Task_Primitives.Operations.
      while Clock < Deadline loop
         null;
      end loop;
   end Timed_Delay;

end System.OS_Primitives;
