------------------------------------------------------------------------------
--  GNAT RUN-TIME COMPONENTS (ESP32-S3 full)
--  S Y S T E M . O S _ P R I M I T I V E S
--  S p e c
------------------------------------------------------------------------------
--  Bareboard implementation for the ESP32-S3 full-tasking runtime.  Provides
--  the small OS-primitives interface the GNARL expects, mapped onto the BB
--  kernel clock (System.BB.Time).  The no-tasking Timed_Delay path is a
--  fallback only; tasking delays route through Task_Primitives.Operations.
------------------------------------------------------------------------------

package System.OS_Primitives is
   pragma Preelaborate;

   Max_Sensible_Delay : constant Duration :=
     Duration'Min (183 * 24 * 60 * 60.0, Duration'Last);
   Max_System_Delay   : constant Duration := Max_Sensible_Delay;

   procedure Initialize;
   --  No global state to set up on the bareboard; may be called repeatedly.

   function Clock return Duration;
   pragma Inline (Clock);
   --  Monotonic time since boot, in seconds, from the BB kernel clock.

   Relative          : constant := 0;
   Absolute_Calendar : constant := 1;
   Absolute_RT       : constant := 2;
   --  Mode values for Timed_Delay.  exp_ch9 relies on these exact values.

   procedure Timed_Delay (Time : Duration; Mode : Integer);

end System.OS_Primitives;
