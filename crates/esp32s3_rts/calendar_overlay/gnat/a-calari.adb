------------------------------------------------------------------------------
--                                                                          --
--                         GNAT RUN-TIME COMPONENTS                         --
--                                                                          --
--              A D A . C A L E N D A R . A R I T H M E T I C               --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2005-2025, AdaCore                     --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.                                     --
--                                                                          --
-- As a special exception under Section 7 of GPL version 3, you are granted --
-- additional permissions described in the GCC Runtime Library Exception,   --
-- version 3.1, as published by the Free Software Foundation.               --
--                                                                          --
-- You should have received a copy of the GNU General Public License and    --
-- a copy of the GCC Runtime Library Exception along with this program;     --
-- see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see    --
-- <http://www.gnu.org/licenses/>.                                          --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

--  This is the bare-metal version of this package.  It is written directly
--  against the parent's Modified-Julian-Day representation (a child body sees
--  its parent's private part), so day arithmetic is exact.  The bare runtime
--  has no leap-second table, so Leap_Seconds is always zero.

package body Ada.Calendar.Arithmetic is

   Secs_Per_Day : constant := 86_400;

   --  Helpers operating on the parent's private day representation

   function Whole_Days (Diff : Modified_Julian_Day) return Day_Count;
   --  Truncate a day difference toward zero

   ----------------
   -- Whole_Days --
   ----------------

   function Whole_Days (Diff : Modified_Julian_Day) return Day_Count is
      Rounded : constant Day_Count := Day_Count (Diff);
   begin
      --  Conversion to integer rounds to nearest; step back toward zero when
      --  the rounded value overshot the true (signed) magnitude.

      if Diff >= 0.0 and then Modified_Julian_Day (Rounded) > Diff then
         return Rounded - 1;
      elsif Diff < 0.0 and then Modified_Julian_Day (Rounded) < Diff then
         return Rounded + 1;
      else
         return Rounded;
      end if;
   end Whole_Days;

   ----------------
   -- Difference --
   ----------------

   procedure Difference
     (Left         : Time;
      Right        : Time;
      Days         : out Day_Count;
      Seconds      : out Duration;
      Leap_Seconds : out Leap_Seconds_Count)
   is
      Day_Diff : constant Modified_Julian_Day :=
        Modified_Julian_Day (Left) - Modified_Julian_Day (Right);
      ND       : constant Day_Count := Whole_Days (Day_Diff);
   begin
      Leap_Seconds := 0;
      Days         := ND;

      --  Remainder seconds = total elapsed seconds minus the whole days.
      --  Calendar."-" (Time, Time) yields the elapsed seconds as Duration.

      Seconds :=
        (Left - Right) - Duration (Long_Long_Integer (ND) * Secs_Per_Day);
   end Difference;

   ---------
   -- "+" --
   ---------

   function "+" (Left : Time; Right : Day_Count) return Time is
   begin
      return Time (Modified_Julian_Day (Left) + Modified_Julian_Day (Right));
   exception
      when Constraint_Error =>
         raise Time_Error;
   end "+";

   function "+" (Left : Day_Count; Right : Time) return Time is
   begin
      return Right + Left;
   end "+";

   ---------
   -- "-" --
   ---------

   function "-" (Left : Time; Right : Day_Count) return Time is
   begin
      return Time (Modified_Julian_Day (Left) - Modified_Julian_Day (Right));
   exception
      when Constraint_Error =>
         raise Time_Error;
   end "-";

   function "-" (Left : Time; Right : Time) return Day_Count is
   begin
      return Whole_Days
        (Modified_Julian_Day (Left) - Modified_Julian_Day (Right));
   end "-";

end Ada.Calendar.Arithmetic;
