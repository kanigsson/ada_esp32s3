------------------------------------------------------------------------------
--                                                                          --
--                 GNAT RUN-TIME LIBRARY (GNARL) COMPONENTS                 --
--                                                                          --
--                     S Y S T E M . I N T E R R U P T S                    --
--                                                                          --
--                                  S p e c                                 --
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

--  This is the BARE-BOARD FULL version of this package (ESP32-S3 no-idf
--  'full' profile).  Unlike the restricted (Ravenscar/Jorvik) bare-board
--  s-interr that ships with the embedded profile -- which provides only
--  Install_Restricted_Handlers -- the full profile lifts the Ravenscar
--  interrupt restrictions, so the compiler lowers a protected object with
--  pragma Attach_Handler to the full dynamic machinery: it expects
--  System.Interrupts to export Register_Interrupt_Handler, the
--  Static_/Dynamic_Interrupt_Protection protected bases, Install_Handlers
--  and the dynamic Attach_/Detach_/Exchange_/Current_Handler operations.
--
--  AdaCore ships a full s-interr only for hosted (POSIX) targets, where it
--  is built on a signal-server task and is unportable to bare metal.  This
--  body re-implements the same surface directly on top of the bare-board
--  primitive System.OS_Interface.Attach_Handler (i.e. System.BB.Interrupts)
--  and the existing kernel interrupt wrapper.
--
--  CURRENT SCOPE: the static path (pragma Attach_Handler, Install_Handlers)
--  is fully supported.  The dynamic path (Ada.Interrupts.Attach_Handler /
--  Detach_Handler at run time) is supported for re-pointing a handler; full
--  detach-at-end-of-scope finalization is limited by Configurable_Run_Time
--  (library-level Finalize is not generated).  Interrupt entries and the
--  POSIX.5 signal services have no bare-board meaning and raise Program_Error.

--  Note: the compiler generates direct calls to this interface, via Rtsfind.
--  Any changes to this interface may require corresponding compiler changes.

with System.Tasking;
with System.Tasking.Protected_Objects.Entries;
with System.OS_Interface;

package System.Interrupts is

   pragma Elaborate_Body;

   -------------------------
   -- Constants and types --
   -------------------------

   Default_Interrupt_Priority : constant System.Interrupt_Priority :=
     System.Interrupt_Priority'Last;
   --  Default value used when a pragma Interrupt_Handler or Attach_Handler is
   --  specified without an Interrupt_Priority pragma, see D.3(10).

   type Ada_Interrupt_ID is new System.OS_Interface.Interrupt_Range;
   --  Avoid inheritance by Ada.Interrupts.Interrupt_ID of unwanted operations

   type Interrupt_ID is new System.OS_Interface.Interrupt_Range;

   subtype System_Interrupt_Id is Interrupt_ID;
   --  This synonym is introduced so that the type is accessible through
   --  rtsfind, otherwise the name clashes with its homonym in Ada.Interrupts.

   type Parameterless_Handler is access protected procedure;

   ----------------------
   -- General services --
   ----------------------

   --  Attempt to attach a Handler to an Interrupt to which an Entry is
   --  already bound will raise a Program_Error.

   function Is_Reserved (Interrupt : Interrupt_ID) return Boolean;

   function Is_Entry_Attached (Interrupt : Interrupt_ID) return Boolean;

   function Is_Handler_Attached (Interrupt : Interrupt_ID) return Boolean;

   function Current_Handler
     (Interrupt : Interrupt_ID) return Parameterless_Handler;

   --  Calling the following procedures with New_Handler = null and Static =
   --  true means that we want to modify the current handler regardless of the
   --  previous handler's binding status. (i.e. we do not care whether it is a
   --  dynamic or static handler)

   procedure Attach_Handler
     (New_Handler : Parameterless_Handler;
      Interrupt   : Interrupt_ID;
      Static      : Boolean := False);

   procedure Exchange_Handler
     (Old_Handler : out Parameterless_Handler;
      New_Handler : Parameterless_Handler;
      Interrupt   : Interrupt_ID;
      Static      : Boolean := False);

   procedure Detach_Handler
     (Interrupt : Interrupt_ID;
      Static    : Boolean := False);

   function Reference
     (Interrupt : Interrupt_ID) return System.Address;

   --------------------------------
   -- Interrupt Entries Services --
   --------------------------------

   --  Interrupt entries are not supported on this bare-board runtime; the
   --  routines below raise Program_Error.

   procedure Bind_Interrupt_To_Entry
     (T       : System.Tasking.Task_Id;
      E       : System.Tasking.Task_Entry_Index;
      Int_Ref : System.Address);

   procedure Detach_Interrupt_Entries (T : System.Tasking.Task_Id);

   ------------------------------
   -- POSIX.5 Signals Services --
   ------------------------------

   --  No signal model on bare metal; these raise Program_Error.

   procedure Block_Interrupt (Interrupt : Interrupt_ID);

   procedure Unblock_Interrupt (Interrupt : Interrupt_ID);

   function Unblocked_By
     (Interrupt : Interrupt_ID) return System.Tasking.Task_Id;

   function Is_Blocked (Interrupt : Interrupt_ID) return Boolean;

   procedure Ignore_Interrupt (Interrupt : Interrupt_ID);

   procedure Unignore_Interrupt (Interrupt : Interrupt_ID);

   function Is_Ignored (Interrupt : Interrupt_ID) return Boolean;

   ----------------------
   -- Protection Types --
   ----------------------

   --  Routines and types needed to implement Interrupt_Handler and
   --  Attach_Handler.

   procedure Register_Interrupt_Handler
     (Handler_Addr : System.Address);
   --  Called by the compiler for each pragma Interrupt_Handler, with the
   --  address of the handler, so that a dynamic Attach_Handler can later
   --  verify the handler is one that was registered.

   type Static_Handler_Index is range 0 .. Integer'Last;
   subtype Positive_Static_Handler_Index is
     Static_Handler_Index range 1 .. Static_Handler_Index'Last;

   type Previous_Handler_Item is record
      Interrupt : Interrupt_ID;
      Handler   : Parameterless_Handler;
      Static    : Boolean;
   end record;
   --  Contains all the information needed to restore a previous handler

   type Previous_Handler_Array is array
     (Positive_Static_Handler_Index range <>) of Previous_Handler_Item;

   type New_Handler_Item is record
      Interrupt : Interrupt_ID;
      Handler   : Parameterless_Handler;
   end record;
   --  Contains all the information from an Attach_Handler pragma

   type New_Handler_Array is
     array (Positive_Static_Handler_Index range <>) of New_Handler_Item;

   --  Case (1): only pragma Interrupt_Handler -- dynamic attachment

   type Dynamic_Interrupt_Protection is new
     Tasking.Protected_Objects.Entries.Protection_Entries with null record;

   function Has_Interrupt_Or_Attach_Handler
     (Object : access Dynamic_Interrupt_Protection) return Boolean;
   --  Returns True

   --  Case (2): pragma Attach_Handler -- static attachment

   type Static_Interrupt_Protection
     (Num_Entries        : Tasking.Protected_Objects.Protected_Entry_Index;
      Num_Attach_Handler : Static_Handler_Index)
   is new
     Tasking.Protected_Objects.Entries.Protection_Entries (Num_Entries) with
     record
       Previous_Handlers : Previous_Handler_Array (1 .. Num_Attach_Handler);
     end record;

   function Has_Interrupt_Or_Attach_Handler
     (Object : access Static_Interrupt_Protection) return Boolean;
   --  Returns True

   overriding procedure Finalize (Object : in out Static_Interrupt_Protection);
   --  Restore previous handlers as required by C.3.1(12) then call
   --  Finalize (Protection).

   procedure Install_Handlers
     (Object       : access Static_Interrupt_Protection;
      New_Handlers : New_Handler_Array);
   --  Store the old handlers in Object.Previous_Handlers and install
   --  the new static handlers.

   procedure Install_Restricted_Handlers
     (Prio     : Interrupt_Priority;
      Handlers : New_Handler_Array);
   --  Install the static Handlers for the given interrupts and do not
   --  store previously installed handlers.

end System.Interrupts;
