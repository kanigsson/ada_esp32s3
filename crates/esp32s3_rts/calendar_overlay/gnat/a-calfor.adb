------------------------------------------------------------------------------
--                                                                          --
--                         GNAT RUN-TIME COMPONENTS                         --
--                                                                          --
--               A D A . C A L E N D A R . F O R M A T T I N G              --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                     Copyright (C) 2006-2025, AdaCore                     --
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

--  This is the bare-metal version of this package.  It is written against the
--  parent's public Split / Time_Of and the bare Time_Zones (always UTC), and
--  it avoids 'Image / 'Value (those image/value units are excluded from the
--  bare runtime library) by formatting and parsing decimal digits by hand.
--  The bare runtime has no leap-second table, so Leap_Second is always False
--  on output and merely advances the clock by one second on input.

package body Ada.Calendar.Formatting is

   --------------------------
   -- Local Declarations --
   --------------------------

   function Zone_Secs (Time_Zone : Time_Zones.Time_Offset) return Duration is
     (Duration (Long_Long_Integer (Time_Zone) * 60));
   --  The zone offset expressed in seconds

   procedure Decompose_Seconds
     (Seconds    : Day_Duration;
      Hour       : out Hour_Number;
      Minute     : out Minute_Number;
      Second     : out Second_Number;
      Sub_Second : out Second_Duration);
   --  Break a Day_Duration into hour / minute / second / sub-second

   function UImg (N : Natural) return String;
   --  Unsigned decimal image, no padding, no leading space

   function Pad2 (N : Natural) return String;
   --  Two-digit zero-padded decimal image (N is taken mod 100)

   function Digit (C : Character) return Natural;
   --  Value of a decimal digit character (raises Constraint_Error otherwise)

   function Frac2 (X : Second_Duration) return Natural;
   --  Hundredths of a second, TRUNCATED toward zero (0 .. 99); the language
   --  requires Image to truncate, not round, the displayed fraction

   ----------------------
   -- Decompose_Seconds --
   ----------------------

   procedure Decompose_Seconds
     (Seconds    : Day_Duration;
      Hour       : out Hour_Number;
      Minute     : out Minute_Number;
      Second     : out Second_Number;
      Sub_Second : out Second_Duration)
   is
      Secs  : constant Day_Duration :=
        (if Seconds >= 86_400.0 then Day_Duration'Pred (86_400.0)
         else Seconds);
      Whole : Natural := Natural (Secs);
   begin
      --  Natural (Secs) rounds; step back if it overshot (Secs >= 0)

      if Day_Duration (Whole) > Secs then
         Whole := Whole - 1;
      end if;

      Hour       := Whole / 3600;
      Minute     := (Whole / 60) mod 60;
      Second     := Whole mod 60;
      Sub_Second := Second_Duration (Secs - Day_Duration (Whole));
   end Decompose_Seconds;

   ----------
   -- UImg --
   ----------

   function UImg (N : Natural) return String is
   begin
      if N < 10 then
         return (1 => Character'Val (Character'Pos ('0') + N));
      else
         return UImg (N / 10) & UImg (N mod 10);
      end if;
   end UImg;

   ----------
   -- Pad2 --
   ----------

   function Pad2 (N : Natural) return String is
      M : constant Natural := N mod 100;
   begin
      return (Character'Val (Character'Pos ('0') + M / 10),
              Character'Val (Character'Pos ('0') + M mod 10));
   end Pad2;

   -----------
   -- Digit --
   -----------

   function Digit (C : Character) return Natural is
   begin
      if C in '0' .. '9' then
         return Character'Pos (C) - Character'Pos ('0');
      else
         raise Constraint_Error;
      end if;
   end Digit;

   -----------
   -- Frac2 --
   -----------

   function Frac2 (X : Second_Duration) return Natural is
      HS : Natural := Natural (X * 100);
   begin
      --  X * 100 is a Duration; Natural (..) rounds, so step back if it
      --  overshot the true value (truncation toward zero, X >= 0).

      if Duration (HS) > X * 100 then
         HS := HS - 1;
      end if;

      return (if HS > 99 then 99 else HS);
   end Frac2;

   -----------------
   -- Day_Of_Week --
   -----------------

   function Day_Of_Week (Date : Time) return Day_Name is
      Y  : Year_Number;
      M  : Month_Number;
      D  : Day_Number;
      DS : Day_Duration;
      MM : Integer;
      YY : Integer;
   begin
      Ada.Calendar.Split (Date, Y, M, D, DS);

      MM := M;
      YY := Y;

      if MM <= 2 then
         MM := MM + 12;
         YY := YY - 1;
      end if;

      --  Zeller's congruence (Gregorian).  H = 0 is Saturday.

      declare
         K : constant Integer := YY mod 100;
         J : constant Integer := YY / 100;
         H : constant Integer :=
           (D + (13 * (MM + 1)) / 5 + K + K / 4 + J / 4 + 5 * J) mod 7;
      begin
         --  Map Zeller's value (0=Sat) onto Day_Name (0=Monday)

         return Day_Name'Val ((H + 5) mod 7);
      end;
   end Day_Of_Week;

   ----------
   -- Year --
   ----------

   function Year
     (Date      : Time;
      Time_Zone : Time_Zones.Time_Offset := 0) return Year_Number
   is
      Y  : Year_Number;
      M  : Month_Number;
      D  : Day_Number;
      DS : Day_Duration;
   begin
      Ada.Calendar.Split (Date + Zone_Secs (Time_Zone), Y, M, D, DS);
      return Y;
   end Year;

   -----------
   -- Month --
   -----------

   function Month
     (Date      : Time;
      Time_Zone : Time_Zones.Time_Offset := 0) return Month_Number
   is
      Y  : Year_Number;
      M  : Month_Number;
      D  : Day_Number;
      DS : Day_Duration;
   begin
      Ada.Calendar.Split (Date + Zone_Secs (Time_Zone), Y, M, D, DS);
      return M;
   end Month;

   ---------
   -- Day --
   ---------

   function Day
     (Date      : Time;
      Time_Zone : Time_Zones.Time_Offset := 0) return Day_Number
   is
      Y  : Year_Number;
      M  : Month_Number;
      D  : Day_Number;
      DS : Day_Duration;
   begin
      Ada.Calendar.Split (Date + Zone_Secs (Time_Zone), Y, M, D, DS);
      return D;
   end Day;

   ----------
   -- Hour --
   ----------

   function Hour
     (Date      : Time;
      Time_Zone : Time_Zones.Time_Offset := 0) return Hour_Number
   is
      Y  : Year_Number;
      M  : Month_Number;
      D  : Day_Number;
      DS : Day_Duration;
      H  : Hour_Number;
      Mi : Minute_Number;
      S  : Second_Number;
      SS : Second_Duration;
   begin
      Ada.Calendar.Split (Date + Zone_Secs (Time_Zone), Y, M, D, DS);
      Decompose_Seconds (DS, H, Mi, S, SS);
      return H;
   end Hour;

   ------------
   -- Minute --
   ------------

   function Minute
     (Date      : Time;
      Time_Zone : Time_Zones.Time_Offset := 0) return Minute_Number
   is
      Y  : Year_Number;
      M  : Month_Number;
      D  : Day_Number;
      DS : Day_Duration;
      H  : Hour_Number;
      Mi : Minute_Number;
      S  : Second_Number;
      SS : Second_Duration;
   begin
      Ada.Calendar.Split (Date + Zone_Secs (Time_Zone), Y, M, D, DS);
      Decompose_Seconds (DS, H, Mi, S, SS);
      return Mi;
   end Minute;

   ------------
   -- Second --
   ------------

   function Second (Date : Time) return Second_Number is
      Y  : Year_Number;
      M  : Month_Number;
      D  : Day_Number;
      DS : Day_Duration;
      H  : Hour_Number;
      Mi : Minute_Number;
      S  : Second_Number;
      SS : Second_Duration;
   begin
      Ada.Calendar.Split (Date, Y, M, D, DS);
      Decompose_Seconds (DS, H, Mi, S, SS);
      return S;
   end Second;

   ----------------
   -- Sub_Second --
   ----------------

   function Sub_Second (Date : Time) return Second_Duration is
      Y  : Year_Number;
      M  : Month_Number;
      D  : Day_Number;
      DS : Day_Duration;
      H  : Hour_Number;
      Mi : Minute_Number;
      S  : Second_Number;
      SS : Second_Duration;
   begin
      Ada.Calendar.Split (Date, Y, M, D, DS);
      Decompose_Seconds (DS, H, Mi, S, SS);
      return SS;
   end Sub_Second;

   ----------------
   -- Seconds_Of --
   ----------------

   function Seconds_Of
     (Hour       : Hour_Number;
      Minute     : Minute_Number;
      Second     : Second_Number := 0;
      Sub_Second : Second_Duration := 0.0) return Day_Duration
   is
   begin
      return Day_Duration (Hour * 3600 + Minute * 60 + Second)
        + Day_Duration (Sub_Second);
   end Seconds_Of;

   -----------
   -- Split --
   -----------

   procedure Split
     (Seconds    : Day_Duration;
      Hour       : out Hour_Number;
      Minute     : out Minute_Number;
      Second     : out Second_Number;
      Sub_Second : out Second_Duration)
   is
   begin
      Decompose_Seconds (Seconds, Hour, Minute, Second, Sub_Second);
   end Split;

   procedure Split
     (Date       : Time;
      Year       : out Year_Number;
      Month      : out Month_Number;
      Day        : out Day_Number;
      Hour       : out Hour_Number;
      Minute     : out Minute_Number;
      Second     : out Second_Number;
      Sub_Second : out Second_Duration;
      Time_Zone  : Time_Zones.Time_Offset := 0)
   is
      DS : Day_Duration;
   begin
      Ada.Calendar.Split
        (Date + Zone_Secs (Time_Zone), Year, Month, Day, DS);
      Decompose_Seconds (DS, Hour, Minute, Second, Sub_Second);
   end Split;

   procedure Split
     (Date        : Time;
      Year        : out Year_Number;
      Month       : out Month_Number;
      Day         : out Day_Number;
      Hour        : out Hour_Number;
      Minute      : out Minute_Number;
      Second      : out Second_Number;
      Sub_Second  : out Second_Duration;
      Leap_Second : out Boolean;
      Time_Zone   : Time_Zones.Time_Offset := 0)
   is
   begin
      Leap_Second := False;
      Split
        (Date, Year, Month, Day, Hour, Minute, Second, Sub_Second, Time_Zone);
   end Split;

   procedure Split
     (Date        : Time;
      Year        : out Year_Number;
      Month       : out Month_Number;
      Day         : out Day_Number;
      Seconds     : out Day_Duration;
      Leap_Second : out Boolean;
      Time_Zone   : Time_Zones.Time_Offset := 0)
   is
   begin
      Leap_Second := False;
      Ada.Calendar.Split
        (Date + Zone_Secs (Time_Zone), Year, Month, Day, Seconds);
   end Split;

   -------------
   -- Time_Of --
   -------------

   function Time_Of
     (Year        : Year_Number;
      Month       : Month_Number;
      Day         : Day_Number;
      Hour        : Hour_Number;
      Minute      : Minute_Number;
      Second      : Second_Number;
      Sub_Second  : Second_Duration := 0.0;
      Leap_Second : Boolean := False;
      Time_Zone   : Time_Zones.Time_Offset := 0) return Time
   is
      DS : Day_Duration :=
        Seconds_Of (Hour, Minute, Second, Sub_Second);
   begin
      if Leap_Second then
         DS := DS + 1.0;
      end if;

      return Ada.Calendar.Time_Of (Year, Month, Day, DS)
        - Zone_Secs (Time_Zone);
   end Time_Of;

   function Time_Of
     (Year        : Year_Number;
      Month       : Month_Number;
      Day         : Day_Number;
      Seconds     : Day_Duration := 0.0;
      Leap_Second : Boolean := False;
      Time_Zone   : Time_Zones.Time_Offset := 0) return Time
   is
      DS : Day_Duration := Seconds;
   begin
      if Leap_Second then
         DS := DS + 1.0;
      end if;

      return Ada.Calendar.Time_Of (Year, Month, Day, DS)
        - Zone_Secs (Time_Zone);
   end Time_Of;

   -----------
   -- Image --
   -----------

   function Image
     (Date                  : Time;
      Include_Time_Fraction : Boolean := False;
      Time_Zone             : Time_Zones.Time_Offset := 0) return String
   is
      Y  : Year_Number;
      M  : Month_Number;
      D  : Day_Number;
      H  : Hour_Number;
      Mi : Minute_Number;
      S  : Second_Number;
      SS : Second_Duration;

      Base : String (1 .. 19);
   begin
      Split (Date, Y, M, D, H, Mi, S, SS, Time_Zone);

      Base := Pad2 (Y / 100) & Pad2 (Y mod 100) & "-" & Pad2 (M) & "-"
        & Pad2 (D) & " " & Pad2 (H) & ":" & Pad2 (Mi) & ":" & Pad2 (S);

      if Include_Time_Fraction then
         return Base & "." & Pad2 (Frac2 (SS));
      else
         return Base;
      end if;
   end Image;

   function Image
     (Elapsed_Time          : Duration;
      Include_Time_Fraction : Boolean := False) return String
   is
      Neg   : constant Boolean := Elapsed_Time < 0.0;
      A     : constant Duration := abs Elapsed_Time;
      Whole : Long_Long_Integer := Long_Long_Integer (A);
      Frac  : Second_Duration;
   begin
      --  Long_Long_Integer (A) rounds; step back if it overshot

      if Duration (Whole) > A then
         Whole := Whole - 1;
      end if;

      Frac := Second_Duration (A - Duration (Whole));

      declare
         Hours   : constant Natural := Natural (Whole / 3600);
         Minutes : constant Natural := Natural ((Whole / 60) mod 60);
         Secs    : constant Natural := Natural (Whole mod 60);
         Sign    : constant String := (if Neg then "-" else "");
         H_Img   : constant String := UImg (Hours);
         H_Pad   : constant String :=
           (if H_Img'Length >= 2 then H_Img else "0" & H_Img);
         Base    : constant String :=
           Sign & H_Pad & ":" & Pad2 (Minutes) & ":" & Pad2 (Secs);
      begin
         if Include_Time_Fraction then
            return Base & "." & Pad2 (Frac2 (Frac));
         else
            return Base;
         end if;
      end;
   end Image;

   -----------
   -- Value --
   -----------

   function Value
     (Date      : String;
      Time_Zone : Time_Zones.Time_Offset := 0) return Time
   is
      F : constant Integer := Date'First;

      function V2 (Off : Integer) return Natural is
        (Digit (Date (F + Off)) * 10 + Digit (Date (F + Off + 1)));

      Year   : Natural;
      Month  : Natural;
      Day    : Natural;
      Hour   : Natural;
      Minute : Natural;
      Second : Natural;
      Sub    : Second_Duration := 0.0;
   begin
      --  Expected layout: "YYYY-MM-DD HH:MM:SS" with an optional ".ss" tail

      if Date'Length < 19
        or else Date (F + 4) /= '-'
        or else Date (F + 7) /= '-'
        or else Date (F + 13) /= ':'
        or else Date (F + 16) /= ':'
      then
         raise Constraint_Error;
      end if;

      Year   := V2 (0) * 100 + V2 (2);
      Month  := V2 (5);
      Day    := V2 (8);
      Hour   := V2 (11);
      Minute := V2 (14);
      Second := V2 (17);

      --  Reject out-of-range fields (Value raises Constraint_Error rather
      --  than letting an out-of-range value reach the constrained subtypes,
      --  whose checks may be suppressed in the runtime build).

      if Month not in 1 .. 12
        or else Day not in 1 .. 31
        or else Hour > 23
        or else Minute > 59
        or else Second > 59
      then
         raise Constraint_Error;
      end if;

      if Date'Length >= 22 and then Date (F + 19) = '.' then
         Sub := Second_Duration
           (Duration (Digit (Date (F + 20)) * 10 + Digit (Date (F + 21)))
            / 100);
      end if;

      return Time_Of
        (Year, Month, Day, Hour, Minute, Second, Sub,
         Time_Zone => Time_Zone);
   end Value;

   function Value (Elapsed_Time : String) return Duration is
      F      : Integer := Elapsed_Time'First;
      L      : constant Integer := Elapsed_Time'Last;
      Neg    : Boolean := False;
      Hours  : Natural := 0;
      Minute : Natural;
      Second : Natural;
      Sub    : Duration := 0.0;
      P      : Integer;
   begin
      if F > L then
         raise Constraint_Error;
      end if;

      if Elapsed_Time (F) = '-' then
         Neg := True;
         F := F + 1;
      end if;

      --  Hours: one or more digits up to the first ':'

      P := F;
      while P <= L and then Elapsed_Time (P) /= ':' loop
         Hours := Hours * 10 + Digit (Elapsed_Time (P));
         P := P + 1;
      end loop;

      --  Need ":MM:SS" after the hour field

      if P + 5 > L or else Elapsed_Time (P) /= ':'
        or else Elapsed_Time (P + 3) /= ':'
      then
         raise Constraint_Error;
      end if;

      Minute :=
        Digit (Elapsed_Time (P + 1)) * 10 + Digit (Elapsed_Time (P + 2));
      Second :=
        Digit (Elapsed_Time (P + 4)) * 10 + Digit (Elapsed_Time (P + 5));

      if Minute > 59 or else Second > 59 then
         raise Constraint_Error;
      end if;

      if P + 8 <= L and then Elapsed_Time (P + 6) = '.' then
         Sub := Duration
           (Digit (Elapsed_Time (P + 7)) * 10 + Digit (Elapsed_Time (P + 8)))
           / 100;
      end if;

      declare
         R : constant Duration :=
           Duration (Hours * 3600 + Minute * 60 + Second) + Sub;
      begin
         return (if Neg then -R else R);
      end;
   end Value;

end Ada.Calendar.Formatting;
