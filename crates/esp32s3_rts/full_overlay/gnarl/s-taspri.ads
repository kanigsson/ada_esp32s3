------------------------------------------------------------------------------
--  GNAT RUN-TIME COMPONENTS (ESP32-S3 full)
--  S Y S T E M . T A S K _ P R I M I T I V E S
--  S p e c
------------------------------------------------------------------------------
--  ESP32-S3 full-tasking version.  Extends the Ravenscar bareboard          --
--  Task_Primitives with the Lock and Suspension_Object types the full GNARL
--  requires (the restricted version only declared Private_Data).  Locks use
--  the priority-ceiling + Fair_Lock model (see s-oslock.ads); the operations
--  are in System.Task_Primitives.Operations (s-taprop.adb).
------------------------------------------------------------------------------

with System.OS_Interface;
with System.OS_Locks;
with System.Multiprocessors.Fair_Locks;

package System.Task_Primitives is
   pragma Preelaborate;

   type Task_Body_Access is access procedure;
   --  Pointer to the task body's entry point

   type Lock is limited private;
   --  Should be used for protection of low-level objects (protected-object and
   --  ATCB locks).  Mutual exclusion via priority ceiling + Fair_Lock.

   type Suspension_Object is limited private;
   --  Synchronization primitive backing Ada.Synchronous_Task_Control

   type Private_Data is limited private;
   --  Per-task GNULLI data, included in the ATCB

   subtype Task_Address is System.Address;
   Task_Address_Size : constant := Standard'Address_Size;

   Alternate_Stack_Size : constant := 0;
   --  No alternate signal stack on this platform

private

   type Lock is limited record
      RTS : aliased System.OS_Locks.RTS_Lock;
   end record;

   type Suspension_Object is limited record
      State   : Boolean := False;
      pragma Atomic (State);
      --  Status of the suspension object (signalled or not)

      Waiting : Boolean := False;
      --  A task is waiting on this suspension object

      Waiter  : aliased System.OS_Interface.Thread_Id :=
                  System.OS_Interface.Null_Thread_Id;
      --  The thread blocked in Suspend_Until_True, to be woken by Set_True

      L       : System.Multiprocessors.Fair_Locks.Fair_Lock;
      --  Protects the fields above against concurrent access across cores
   end record;

   type Private_Data is limited record
      Thread_Desc : aliased System.OS_Interface.Thread_Descriptor;
      --  Thread descriptor associated to the ATCB to which it belongs

      Thread : aliased System.OS_Interface.Thread_Id :=
                 System.OS_Interface.Null_Thread_Id;
      pragma Atomic (Thread);
      --  Thread Id associated to the ATCB (also read by GDB)

      Lwp : aliased System.Address := System.Null_Address;
      --  Duplicates Thread; read by gdb over the remote protocol

      L : aliased System.OS_Locks.RTS_Lock;
      --  Per-task ATCB lock (taken by Write_Lock (T : Task_Id))

      Owned_Stack : System.Address := System.Null_Address;
      --  If non-null, the primary stack was allocated by Create_Task (via
      --  Alloc_Task_Stack) and must be returned to the heap by Finalize_TCB.
      --  Null for a preallocated (compiler-provided) stack, which we must not
      --  free.  See System.Task_Primitives.Operations.Finalize_TCB.
   end record;

end System.Task_Primitives;
