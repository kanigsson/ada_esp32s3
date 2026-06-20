------------------------------------------------------------------------------
--                                                                          --
--                 GNAT RUN-TIME LIBRARY (GNARL) COMPONENTS                 --
--                                                                          --
--                     S Y S T E M . I N T E R R U P T S                    --
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

--  This is the BARE-BOARD FULL version of this package body (ESP32-S3 no-idf
--  'full' profile).  See the spec for the rationale.  The actual hardware
--  attach/dispatch/ceiling machinery already lives in System.BB.Interrupts
--  (reached through System.OS_Interface) and the kernel interrupt vectors;
--  this body only layers the GNARL surface (the protection types, handler
--  registration and the dynamic operations) on top of it.

with Ada.Unchecked_Conversion;

with System.Storage_Elements;
with System.Interrupt_Management;
--  System.Tasking.Protected_Objects.Entries is already withed by the spec.

package body System.Interrupts is

   package IMNG renames System.Interrupt_Management;
   package POE  renames System.Tasking.Protected_Objects.Entries;

   ----------------
   -- Local Data --
   ----------------

   type Handler_Entry is record
      Handler : Parameterless_Handler;
      --  The protected subprogram currently bound to this interrupt

      PO_Priority : Interrupt_Priority;
      --  Priority of the protected object in which the handler is declared.
      --  Retained for fidelity; the bare-board controller programming ignores
      --  it (the Xtensa interrupt level is fixed per source).

      Static : Boolean;
      --  True when the binding came from a pragma Attach_Handler (a static
      --  handler), which a dynamic Detach_Handler is not allowed to remove.
   end record;
   pragma Suppress_Initialization (Handler_Entry);

   type Handlers_Table is array (Interrupt_ID) of Handler_Entry;
   pragma Suppress_Initialization (Handlers_Table);

   User_Handlers : Handlers_Table :=
                     (others => (null, Interrupt_Priority'First, False));
   --  Table of the user handlers, indexed by interrupt. Explicitly
   --  initialized so interrupts without an attached handler are detectable.

   Attached : array (Interrupt_ID) of Boolean := (others => False);
   --  True once the runtime umbrella handler has been installed in the kernel
   --  for an interrupt. The bare-board primitive accepts a single attach per
   --  interrupt, so we install the umbrella once and thereafter just re-point
   --  User_Handlers to redirect it.

   --  Handler registration list (pragma Interrupt_Handler)

   type Registered_Handler;
   type R_Link is access all Registered_Handler;

   type Registered_Handler is record
      H    : System.Address;
      Next : R_Link;
   end record;

   Registered_Handlers : R_Link := null;

   -----------------------
   -- Local Subprograms --
   -----------------------

   procedure Default_Handler (Interrupt : System.OS_Interface.Interrupt_ID);
   --  Runtime umbrella handler: dispatches to the current user handler

   procedure Install_Umbrella
     (Interrupt : Interrupt_ID; Prio : Interrupt_Priority);
   --  Install (once) the umbrella handler for a hardware interrupt

   function Is_Registered (Handler : Parameterless_Handler) return Boolean;
   --  True if Handler was registered via pragma Interrupt_Handler. A null
   --  handler is always considered registered.

   ---------------------
   -- Default_Handler --
   ---------------------

   procedure Default_Handler (Interrupt : System.OS_Interface.Interrupt_ID) is
      Handler : constant Parameterless_Handler :=
                  User_Handlers (Interrupt_ID (Interrupt)).Handler;
   begin
      if Handler = null then
         raise Program_Error;
      end if;

      --  An exception propagated from a handler invoked by an interrupt must
      --  have no effect (ARM C.3 par. 7), so wrap the call.

      begin
         Handler.all;
      exception
         when others =>
            null;
      end;
   end Default_Handler;

   ----------------------
   -- Install_Umbrella --
   ----------------------

   procedure Install_Umbrella
     (Interrupt : Interrupt_ID; Prio : Interrupt_Priority) is
   begin
      if not Attached (Interrupt) then
         System.OS_Interface.Attach_Handler
           (Default_Handler'Access,
            System.OS_Interface.Interrupt_ID (Interrupt),
            Prio);
         Attached (Interrupt) := True;
      end if;

      User_Handlers (Interrupt).PO_Priority := Prio;
   end Install_Umbrella;

   -----------------
   -- Is_Reserved --
   -----------------

   function Is_Reserved (Interrupt : Interrupt_ID) return Boolean is
   begin
      return IMNG.Reserve (IMNG.Interrupt_ID (Integer (Interrupt)));
   end Is_Reserved;

   -----------------------
   -- Is_Entry_Attached --
   -----------------------

   function Is_Entry_Attached (Interrupt : Interrupt_ID) return Boolean is
      pragma Unreferenced (Interrupt);
   begin
      --  Interrupt entries are not supported on this runtime
      return False;
   end Is_Entry_Attached;

   -------------------------
   -- Is_Handler_Attached --
   -------------------------

   function Is_Handler_Attached (Interrupt : Interrupt_ID) return Boolean is
   begin
      return User_Handlers (Interrupt).Handler /= null;
   end Is_Handler_Attached;

   ---------------------
   -- Current_Handler --
   ---------------------

   function Current_Handler
     (Interrupt : Interrupt_ID) return Parameterless_Handler is
   begin
      return User_Handlers (Interrupt).Handler;
   end Current_Handler;

   --------------------
   -- Attach_Handler --
   --------------------

   procedure Attach_Handler
     (New_Handler : Parameterless_Handler;
      Interrupt   : Interrupt_ID;
      Static      : Boolean := False) is
   begin
      if Is_Reserved (Interrupt) then
         raise Program_Error with "interrupt" &
           Interrupt_ID'Image (Interrupt) & " is reserved";
      end if;

      --  A dynamic attach (Static = False, non-null handler) requires the
      --  handler to have been registered via pragma Interrupt_Handler.

      if not Static and then New_Handler /= null
        and then not Is_Registered (New_Handler)
      then
         raise Program_Error with
           "attempt to attach an unregistered interrupt handler";
      end if;

      --  A dynamic attach may not overwrite a static handler

      if not Static and then User_Handlers (Interrupt).Static then
         raise Program_Error with
           "trying to overwrite a static interrupt handler";
      end if;

      User_Handlers (Interrupt).Handler := New_Handler;
      User_Handlers (Interrupt).Static  := Static;

      if New_Handler /= null then
         Install_Umbrella (Interrupt, Default_Interrupt_Priority);
      end if;
   end Attach_Handler;

   ----------------------
   -- Exchange_Handler --
   ----------------------

   procedure Exchange_Handler
     (Old_Handler : out Parameterless_Handler;
      New_Handler : Parameterless_Handler;
      Interrupt   : Interrupt_ID;
      Static      : Boolean := False) is
   begin
      if Is_Reserved (Interrupt) then
         raise Program_Error with "interrupt" &
           Interrupt_ID'Image (Interrupt) & " is reserved";
      end if;

      Old_Handler := User_Handlers (Interrupt).Handler;
      Attach_Handler (New_Handler, Interrupt, Static);
   end Exchange_Handler;

   --------------------
   -- Detach_Handler --
   --------------------

   procedure Detach_Handler
     (Interrupt : Interrupt_ID;
      Static    : Boolean := False) is
   begin
      if Is_Reserved (Interrupt) then
         raise Program_Error with "interrupt" &
           Interrupt_ID'Image (Interrupt) & " is reserved";
      end if;

      --  A dynamic detach may not remove a static handler

      if not Static and then User_Handlers (Interrupt).Static then
         raise Program_Error with
           "trying to detach a static interrupt handler";
      end if;

      --  The kernel umbrella stays installed (the bare-board layer has no
      --  detach primitive); clearing the table makes a subsequent interrupt
      --  spurious.

      User_Handlers (Interrupt).Handler := null;
      User_Handlers (Interrupt).Static  := False;
   end Detach_Handler;

   ---------------
   -- Reference --
   ---------------

   function Reference (Interrupt : Interrupt_ID) return System.Address is
   begin
      if Is_Reserved (Interrupt) then
         raise Program_Error with "interrupt" &
           Interrupt_ID'Image (Interrupt) & " is reserved";
      end if;

      return System.Storage_Elements.To_Address
               (System.Storage_Elements.Integer_Address (Interrupt));
   end Reference;

   -----------------------------
   -- Bind_Interrupt_To_Entry --
   -----------------------------

   procedure Bind_Interrupt_To_Entry
     (T       : System.Tasking.Task_Id;
      E       : System.Tasking.Task_Entry_Index;
      Int_Ref : System.Address)
   is
      pragma Unreferenced (T, E, Int_Ref);
   begin
      raise Program_Error with "interrupt entries are not supported";
   end Bind_Interrupt_To_Entry;

   ------------------------------
   -- Detach_Interrupt_Entries --
   ------------------------------

   procedure Detach_Interrupt_Entries (T : System.Tasking.Task_Id) is
      pragma Unreferenced (T);
   begin
      null;  -- nothing to detach: interrupt entries are unsupported
   end Detach_Interrupt_Entries;

   ---------------------
   -- Block_Interrupt --
   ---------------------

   procedure Block_Interrupt (Interrupt : Interrupt_ID) is
      pragma Unreferenced (Interrupt);
   begin
      raise Program_Error with "Block_Interrupt is not supported";
   end Block_Interrupt;

   -----------------------
   -- Unblock_Interrupt --
   -----------------------

   procedure Unblock_Interrupt (Interrupt : Interrupt_ID) is
      pragma Unreferenced (Interrupt);
   begin
      raise Program_Error with "Unblock_Interrupt is not supported";
   end Unblock_Interrupt;

   ------------------
   -- Unblocked_By --
   ------------------

   function Unblocked_By
     (Interrupt : Interrupt_ID) return System.Tasking.Task_Id
   is
      pragma Unreferenced (Interrupt);
   begin
      return System.Tasking.Null_Task;
   end Unblocked_By;

   ----------------
   -- Is_Blocked --
   ----------------

   function Is_Blocked (Interrupt : Interrupt_ID) return Boolean is
      pragma Unreferenced (Interrupt);
   begin
      return False;
   end Is_Blocked;

   ----------------------
   -- Ignore_Interrupt --
   ----------------------

   procedure Ignore_Interrupt (Interrupt : Interrupt_ID) is
      pragma Unreferenced (Interrupt);
   begin
      raise Program_Error with "Ignore_Interrupt is not supported";
   end Ignore_Interrupt;

   ------------------------
   -- Unignore_Interrupt --
   ------------------------

   procedure Unignore_Interrupt (Interrupt : Interrupt_ID) is
      pragma Unreferenced (Interrupt);
   begin
      raise Program_Error with "Unignore_Interrupt is not supported";
   end Unignore_Interrupt;

   ----------------
   -- Is_Ignored --
   ----------------

   function Is_Ignored (Interrupt : Interrupt_ID) return Boolean is
      pragma Unreferenced (Interrupt);
   begin
      return False;
   end Is_Ignored;

   -------------------
   -- Is_Registered --
   -------------------

   function Is_Registered (Handler : Parameterless_Handler) return Boolean is
      Ptr : R_Link := Registered_Handlers;

      type Acc_Proc is access procedure;

      type Fat_Ptr is record
         Object_Addr  : System.Address;
         Handler_Addr : Acc_Proc;
      end record;

      function To_Fat_Ptr is new Ada.Unchecked_Conversion
        (Parameterless_Handler, Fat_Ptr);

      Fat : Fat_Ptr;

   begin
      if Handler = null then
         return True;
      end if;

      Fat := To_Fat_Ptr (Handler);

      while Ptr /= null loop
         if Ptr.H = Fat.Handler_Addr.all'Address then
            return True;
         end if;

         Ptr := Ptr.Next;
      end loop;

      return False;
   end Is_Registered;

   --------------------------------
   -- Register_Interrupt_Handler --
   --------------------------------

   procedure Register_Interrupt_Handler (Handler_Addr : System.Address) is
   begin
      pragma Assert (Handler_Addr /= System.Null_Address);

      Registered_Handlers :=
        new Registered_Handler'(H    => Handler_Addr,
                                Next => Registered_Handlers);
   end Register_Interrupt_Handler;

   -------------------------------------
   -- Has_Interrupt_Or_Attach_Handler --
   -------------------------------------

   function Has_Interrupt_Or_Attach_Handler
     (Object : access Dynamic_Interrupt_Protection) return Boolean
   is
      pragma Unreferenced (Object);
   begin
      return True;
   end Has_Interrupt_Or_Attach_Handler;

   function Has_Interrupt_Or_Attach_Handler
     (Object : access Static_Interrupt_Protection) return Boolean
   is
      pragma Unreferenced (Object);
   begin
      return True;
   end Has_Interrupt_Or_Attach_Handler;

   ----------------------
   -- Install_Handlers --
   ----------------------

   procedure Install_Handlers
     (Object       : access Static_Interrupt_Protection;
      New_Handlers : New_Handler_Array)
   is
      Prio : constant Interrupt_Priority :=
               (if Object.Ceiling in Interrupt_Priority
                then Object.Ceiling
                else Default_Interrupt_Priority);
   begin
      for N in New_Handlers'Range loop

         --  Save the previously installed handler so Finalize can restore it

         Object.Previous_Handlers (N).Interrupt := New_Handlers (N).Interrupt;
         Object.Previous_Handlers (N).Static    :=
           User_Handlers (New_Handlers (N).Interrupt).Static;
         Object.Previous_Handlers (N).Handler   :=
           User_Handlers (New_Handlers (N).Interrupt).Handler;

         --  Install the new static handler

         User_Handlers (New_Handlers (N).Interrupt).Handler :=
           New_Handlers (N).Handler;
         User_Handlers (New_Handlers (N).Interrupt).Static := True;

         Install_Umbrella (New_Handlers (N).Interrupt, Prio);
      end loop;
   end Install_Handlers;

   --------------
   -- Finalize --
   --------------

   procedure Finalize (Object : in out Static_Interrupt_Protection) is
   begin
      --  Restore the handlers that were installed before this PO elaborated
      --  (C.3.1(12)). Note: under Configurable_Run_Time library-level
      --  finalization is not generated, so for a library-level interrupt PO
      --  this runs only if the PO is finalized at scope exit.

      for N in reverse Object.Previous_Handlers'Range loop
         declare
            PH : Previous_Handler_Item renames Object.Previous_Handlers (N);
         begin
            User_Handlers (PH.Interrupt).Handler := PH.Handler;
            User_Handlers (PH.Interrupt).Static  := PH.Static;
         end;
      end loop;

      POE.Finalize (POE.Protection_Entries (Object));
   end Finalize;

   ---------------------------------
   -- Install_Restricted_Handlers --
   ---------------------------------

   procedure Install_Restricted_Handlers
     (Prio     : Interrupt_Priority;
      Handlers : New_Handler_Array) is
   begin
      for J in Handlers'Range loop
         User_Handlers (Handlers (J).Interrupt).Handler :=
           Handlers (J).Handler;
         User_Handlers (Handlers (J).Interrupt).Static := True;
         Install_Umbrella (Handlers (J).Interrupt, Prio);
      end loop;
   end Install_Restricted_Handlers;

end System.Interrupts;
