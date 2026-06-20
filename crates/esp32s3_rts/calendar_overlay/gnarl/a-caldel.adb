------------------------------------------------------------------------------
--                                                                          --
--                 GNAT RUN-TIME LIBRARY (GNARL) COMPONENTS                 --
--                                                                          --
--                   A D A . C A L E N D A R . D E L A Y S                  --
--                                                                          --
--                                  B o d y                                 --
--                                                                          --
--          Copyright (C) 1992-2025, Free Software Foundation, Inc.         --
--                                                                          --
-- GNARL is free software; you can  redistribute it  and/or modify it under --
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
-- GNARL was developed by the GNARL team at Florida State University.       --
-- Extensive contributions were provided by Ada Core Technologies, Inc.     --
--                                                                          --
------------------------------------------------------------------------------

--  This is the bare-metal version of this package.  Rather than route through
--  System.OS_Primitives / Soft_Links (the hosted-OS implementation), it maps
--  the wall-clock delay onto Ada.Real_Time.Delays, which is the SMP-hardened
--  absolute-delay primitive of this runtime.  Both Delay_For and Delay_Until
--  are abort completion points by virtue of Real_Time.Delays.Delay_Until.

with Ada.Real_Time;
with Ada.Real_Time.Delays;

package body Ada.Calendar.Delays is

   use type Ada.Real_Time.Time;

   -----------------
   -- To_Duration --
   -----------------

   function To_Duration (T : Time) return Duration is
   begin
      --  Seconds elapsed since the UNIX epoch (Radix_Time == 1970-01-01 UTC,
      --  the parent's zero point).

      return T - Radix_Time;
   end To_Duration;

   ---------------
   -- Delay_For --
   ---------------

   procedure Delay_For (D : Duration) is
   begin
      Ada.Real_Time.Delays.Delay_Until
        (Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (D));
   end Delay_For;

   -----------------
   -- Delay_Until --
   -----------------

   procedure Delay_Until (T : Time) is
      Now : constant Time := Clock;
      Rel : constant Duration := (if T <= Now then 0.0 else T - Now);
   begin
      Ada.Real_Time.Delays.Delay_Until
        (Ada.Real_Time.Clock + Ada.Real_Time.To_Time_Span (Rel));
   end Delay_Until;

end Ada.Calendar.Delays;
