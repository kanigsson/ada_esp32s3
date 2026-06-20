------------------------------------------------------------------------------
--  GNAT RUN-TIME COMPONENTS (ESP32-S3 full)
--  S Y S T E M . T A S K _ P R I M I T I V E S . O P E R A T I O N S
--  S p e c
------------------------------------------------------------------------------
--  ESP32-S3 full-tasking GNULLI.  This is the STANDARD Task_Primitives.
--  Operations interface (as the full GNARL -- s-tassta / s-tasren -- expects
--  it), implemented over the bare-board BB kernel (s-bbthre, s-osinte,
--  Fair_Locks).  It replaces the restricted Ravenscar bareboard s-taprop.
--  Differences from the host version: bodies map onto the BB executive
--  instead of pthreads; the idle-task / Extended_Priority handling is kept
--  internal so the exported interface uses System.Any_Priority.  The abort
--  family (Abort_Task / Stop / Suspend / Resume / Continue) is the M5
--  frontier and is stubbed for now.
------------------------------------------------------------------------------

with System.Parameters;
with System.Tasking;
with System.OS_Interface;
with System.OS_Locks;
with System.Multiprocessors;

package System.Task_Primitives.Operations is
   pragma Preelaborate;

   package OSI renames System.OS_Interface;
   package ST  renames System.Tasking;

   procedure Initialize (Environment_Task : ST.Task_Id);

   procedure Create_Task
     (T          : ST.Task_Id;
      Wrapper    : System.Address;
      Stack_Size : System.Parameters.Size_Type;
      Priority   : System.Any_Priority;
      Succeeded  : out Boolean);
   pragma Inline (Create_Task);

   procedure Enter_Task (Self_ID : ST.Task_Id);
   pragma Inline (Enter_Task);

   procedure Exit_Task;
   pragma Inline (Exit_Task);

   package ATCB_Allocation is
      function New_ATCB (Entry_Num : ST.Task_Entry_Index) return ST.Task_Id;
      pragma Inline (New_ATCB);
      procedure Free_ATCB (T : ST.Task_Id);
      pragma Inline (Free_ATCB);
   end ATCB_Allocation;

   function New_ATCB (Entry_Num : ST.Task_Entry_Index) return ST.Task_Id
     renames ATCB_Allocation.New_ATCB;

   procedure Initialize_TCB (Self_ID : ST.Task_Id; Succeeded : out Boolean);
   pragma Inline (Initialize_TCB);

   procedure Finalize_TCB (T : ST.Task_Id);
   pragma Inline (Finalize_TCB);

   procedure Abort_Task (T : ST.Task_Id);
   pragma Inline (Abort_Task);

   function Self return ST.Task_Id;
   pragma Inline (Self);

   ------------
   -- Locks  --
   ------------

   type Lock_Level is
     (PO_Level, Global_Task_Level, RTS_Lock_Level, ATCB_Level);

   procedure Initialize_Lock
     (Prio : System.Any_Priority; L : not null access Lock);
   procedure Initialize_Lock
     (L : not null access System.OS_Locks.RTS_Lock; Level : Lock_Level);
   pragma Inline (Initialize_Lock);

   procedure Finalize_Lock (L : not null access Lock);
   procedure Finalize_Lock (L : not null access System.OS_Locks.RTS_Lock);
   pragma Inline (Finalize_Lock);

   procedure Write_Lock
     (L : not null access Lock; Ceiling_Violation : out Boolean);
   procedure Write_Lock (L : not null access System.OS_Locks.RTS_Lock);
   procedure Write_Lock (T : ST.Task_Id);
   pragma Inline (Write_Lock);

   procedure Read_Lock
     (L : not null access Lock; Ceiling_Violation : out Boolean);
   pragma Inline (Read_Lock);

   procedure Unlock (L : not null access Lock);
   procedure Unlock (L : not null access System.OS_Locks.RTS_Lock);
   procedure Unlock (T : ST.Task_Id);
   pragma Inline (Unlock);

   procedure Set_Ceiling
     (L : not null access Lock; Prio : System.Any_Priority);
   pragma Inline (Set_Ceiling);

   procedure Lock_RTS;
   procedure Unlock_RTS;

   ----------------------
   -- Scheduling / time --
   ----------------------

   procedure Yield (Do_Yield : Boolean := True);

   procedure Set_Priority
     (T : ST.Task_Id; Prio : System.Any_Priority;
      Loss_Of_Inheritance : Boolean := False);
   pragma Inline (Set_Priority);

   function Get_Priority (T : ST.Task_Id) return System.Any_Priority;
   pragma Inline (Get_Priority);

   function Monotonic_Clock return Duration;
   pragma Inline (Monotonic_Clock);

   function RT_Resolution return Duration;

   procedure Sleep (Self_ID : ST.Task_Id; Reason : System.Tasking.Task_States);
   pragma Inline (Sleep);

   procedure Timed_Sleep
     (Self_ID  : ST.Task_Id;
      Time     : Duration;
      Mode     : ST.Delay_Modes;
      Reason   : System.Tasking.Task_States;
      Timedout : out Boolean;
      Yielded  : out Boolean);

   procedure Timed_Delay
     (Self_ID : ST.Task_Id; Time : Duration; Mode : ST.Delay_Modes);

   subtype Time is OSI.Time;
   --  Absolute monotonic time in BB/OSI ticks (= System.BB.Time.Time).

   procedure Delay_Until (Self_ID : ST.Task_Id; Abs_Time : Time);
   --  Absolute delay whose wake time is ALREADY in ticks -- no Duration
   --  round-trip (that multiply tears under the L5 alarm tick: the SMP delay
   --  strand).  Mirrors the embedded entry; keeps Common.State bookkeeping.
   pragma Inline (Delay_Until);

   procedure Wakeup (T : ST.Task_Id; Reason : System.Tasking.Task_States);
   pragma Inline (Wakeup);

   ----------------
   -- Task state --
   ----------------

   function Environment_Task return ST.Task_Id;
   pragma Inline (Environment_Task);

   function Get_Thread_Id (T : ST.Task_Id) return OSI.Thread_Id;

   function Is_Valid_Task return Boolean;
   pragma Inline (Is_Valid_Task);

   function Register_Foreign_Thread return ST.Task_Id;

   procedure Stack_Guard (T : ST.Task_Id; On : Boolean);

   function Get_CPU (T : ST.Task_Id) return System.Multiprocessors.CPU;
   function Get_Affinity
     (T : ST.Task_Id) return System.Multiprocessors.CPU_Range;
   procedure Set_Task_Affinity (T : ST.Task_Id);

   function Is_Task_Context return Boolean;
   --  Bareboard-specific: True when not in interrupt context.

   ------------------------
   -- Suspension objects --
   ------------------------

   function Current_State (S : Suspension_Object) return Boolean;
   procedure Set_False (S : in out Suspension_Object);
   procedure Set_True (S : in out Suspension_Object);
   procedure Suspend_Until_True (S : in out Suspension_Object);
   procedure Initialize (S : in out Suspension_Object);
   procedure Finalize (S : in out Suspension_Object);

   ----------------------------
   -- Abort / ATC (M5 stubs) --
   ----------------------------

   function Check_Exit (Self_ID : ST.Task_Id) return Boolean;
   function Check_No_Locks (Self_ID : ST.Task_Id) return Boolean;
   function Suspend_Task
     (T : ST.Task_Id; Thread_Self : OSI.Thread_Id) return Boolean;
   function Resume_Task
     (T : ST.Task_Id; Thread_Self : OSI.Thread_Id) return Boolean;
   procedure Stop_All_Tasks;
   function Stop_Task (T : ST.Task_Id) return Boolean;
   function Continue_Task (T : ST.Task_Id) return Boolean;

private
   Environment_Task_Id : ST.Task_Id;
   --  A variable to hold the environment task id (set in Initialize).
end System.Task_Primitives.Operations;
