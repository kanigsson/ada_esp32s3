------------------------------------------------------------------------------
--  GNAT RUN-TIME COMPONENTS (ESP32-S3 full)
--  S Y S T E M . T A S K _ P R I M I T I V E S . O P E R A T I O N S
--  B o d y
------------------------------------------------------------------------------
--  ESP32-S3 full-tasking GNULLI body, over the BB executive (s-bbthre via
--  System.OS_Interface) + Fair_Locks.  See the spec for the design notes.
------------------------------------------------------------------------------

with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;

with System.Storage_Elements;
with System.Tasking.Debug;
with System.Task_Info;
with System.Multiprocessors.Fair_Locks;
with System.BB.Parameters;
with System.BB.Time;
with System.BB.CPU_Primitives.Multiprocessors;
with System.Memory;
with System.Stack_Checking;

package body System.Task_Primitives.Operations is

   use System.OS_Interface;
   use System.Parameters;
   use System.Storage_Elements;
   use System.Multiprocessors;

   use type System.Tasking.Task_Id;
   use type System.BB.Time.Time;

   Multiprocessor : constant Boolean := CPU'Range_Length /= 1;

   Relative_Mode : constant := 0;
   --  System.OS_Primitives.Relative (delay relative to now)

   Absolute_Calendar_Mode : constant := 1;
   --  System.OS_Primitives.Absolute_Calendar: an absolute deadline in the
   --  Ada.Calendar time base (Clock - Epoch).  Needs an Epoch shift in
   --  Timed_Sleep to reach the raw counter Delay_Until compares against.

   Idle_Priority : constant Integer := Integer (System.Any_Priority'First) - 1;
   --  Idle tasks run below every application priority.

   Single_RTS_Lock : aliased System.OS_Locks.RTS_Lock;
   --  The global RTS lock (Lock_RTS / Unlock_RTS).

   ---------------------
   -- Local Functions --
   ---------------------

   function To_Address is new
     Ada.Unchecked_Conversion (ST.Task_Id, System.Address);
   function To_Task_Id is new
     Ada.Unchecked_Conversion (System.Address, ST.Task_Id);

   function Freq return Time
     is (Time (System.BB.Parameters.Clock_Frequency));

   ------------------------------
   -- Task-stack allocator hook --
   ------------------------------

   --  Optional BSP override for where task stacks are allocated.  If the
   --  application defines the C symbol "__gnat_task_stack_alloc", Create_Task
   --  uses it (e.g. to place task stacks in PSRAM); otherwise stacks come from
   --  the internal Ada heap (System.Memory).  See the full_tasking example's
   --  README for the three configurations (none / stacks-only / all in PSRAM).

   function Stack_Alloc_Hook
     (Size : System.Memory.size_t) return System.Address;
   pragma Import (C, Stack_Alloc_Hook, "__gnat_task_stack_alloc");
   pragma Weak_External (Stack_Alloc_Hook);

   --  Counterpart of Stack_Alloc_Hook: return a terminated task's primary
   --  stack to the heap.  The application implementation MUST serialise the
   --  free against the terminating thread leaving its stack -- it spins until
   --  Thread is no longer the running thread on any CPU (read from the exported
   --  __gnat_running_thread_table) before releasing Stack.  See the example
   --  glue's __gnat_task_stack_free.
   procedure Stack_Free_Hook (Stack : System.Address; Thread : System.Address);
   pragma Import (C, Stack_Free_Hook, "__gnat_task_stack_free");
   pragma Weak_External (Stack_Free_Hook);

   --  Recoverable stack-overflow, stage 1 (precise detection): when a task
   --  starts (Enter_Task runs in the task's own context, so Self is the running
   --  thread), arm a HW watchpoint near its stack limit so an overflow write
   --  faults precisely -- a debug exception caught before the SP runs wild --
   --  instead of the masked cache-error.  The hook reads the running thread's
   --  bottom via __gnat_running_stack_bounds and calls esp_cpu_set_watchpoint;
   --  the application provides it.
   procedure Arm_Stack_Watchpoint_Hook;
   pragma Import (C, Arm_Stack_Watchpoint_Hook, "__gnat_arm_stack_watchpoint");
   pragma Weak_External (Arm_Stack_Watchpoint_Hook);

   function Alloc_Task_Stack
     (Stack_Size : System.Parameters.Size_Type) return System.Address;

   function Alloc_Task_Stack
     (Stack_Size : System.Parameters.Size_Type) return System.Address is
   begin
      if Stack_Alloc_Hook'Address = Null_Address then
         return System.Memory.Alloc (System.Memory.size_t (Stack_Size));
      else
         return Stack_Alloc_Hook (System.Memory.size_t (Stack_Size));
      end if;
   end Alloc_Task_Stack;

   procedure Lock_Generic (L : not null access System.OS_Locks.RTS_Lock);
   procedure Unlock_Generic (L : not null access System.OS_Locks.RTS_Lock);
   --  Shared ceiling + Fair_Lock acquire / release.

   procedure Initialize_Idle (CPU_Id : CPU);
   procedure Initialize_Slave (CPU_Id : System.Multiprocessors.CPU);
   pragma Export (Asm, Initialize_Slave, "__gnat_initialize_slave");
   procedure Idle (Param : Address);

   Idle_Stack_Size : constant System.Storage_Elements.Storage_Count :=
     (System.Storage_Elements.Storage_Count
       (Size_Type'Max (2048, Minimum_Stack_Size)) / Standard'Maximum_Alignment)
     * Standard'Maximum_Alignment;

   type Idle_Stack_Space is
     new Storage_Elements.Storage_Array (1 .. Idle_Stack_Size);
   for Idle_Stack_Space'Alignment use Standard'Maximum_Alignment;

   Idle_Stacks : array (CPU) of Idle_Stack_Space;

   Idle_Stacks_Table : array (CPU) of System.Address;
   pragma Export (Asm, Idle_Stacks_Table, "__gnat_idle_stack_table");

   Idle_Tasks : array (Multiprocessors.CPU) of
                   aliased Tasking.Ada_Task_Control_Block (Entry_Num => 0);

   ----------
   -- Self --
   ----------

   function Self return ST.Task_Id is
   begin
      return To_Task_Id (System.OS_Interface.Get_ATCB);
   end Self;

   -----------------
   -- Lock_Generic --
   -----------------

   procedure Lock_Generic (L : not null access System.OS_Locks.RTS_Lock) is
      Self_Id : constant ST.Task_Id := Self;
      Caller  : constant Any_Priority := Get_Priority (Self_Id);
   begin
      Set_Priority (Self_Id, L.Ceiling);
      if Multiprocessor then
         Fair_Locks.Lock (L.L);
      end if;
      L.Caller_Priority := Caller;
   end Lock_Generic;

   procedure Unlock_Generic (L : not null access System.OS_Locks.RTS_Lock) is
      Self_Id : constant ST.Task_Id := Self;
      Caller  : constant Any_Priority := L.Caller_Priority;
   begin
      if Multiprocessor then
         Fair_Locks.Unlock (L.L);
      end if;
      Set_Priority (Self_Id, Caller);
   end Unlock_Generic;

   ---------------------
   -- Initialize_Lock --
   ---------------------

   procedure Initialize_Lock
     (Prio : System.Any_Priority; L : not null access Lock) is
   begin
      L.RTS.Ceiling := Prio;
      L.RTS.Caller_Priority := System.Any_Priority'First;
      if Multiprocessor then
         Fair_Locks.Initialize (L.RTS.L);
      end if;
   end Initialize_Lock;

   procedure Initialize_Lock
     (L : not null access System.OS_Locks.RTS_Lock; Level : Lock_Level)
   is
      pragma Unreferenced (Level);
   begin
      L.Ceiling := System.Any_Priority'Last;
      L.Caller_Priority := System.Any_Priority'First;
      if Multiprocessor then
         Fair_Locks.Initialize (L.L);
      end if;
   end Initialize_Lock;

   -------------------
   -- Finalize_Lock --
   -------------------

   procedure Finalize_Lock (L : not null access Lock) is null;
   procedure Finalize_Lock
     (L : not null access System.OS_Locks.RTS_Lock) is null;

   ----------------
   -- Write_Lock --
   ----------------

   procedure Write_Lock
     (L : not null access Lock; Ceiling_Violation : out Boolean) is
   begin
      if Get_Priority (Self) > L.RTS.Ceiling then
         Ceiling_Violation := True;
         return;
      end if;
      Ceiling_Violation := False;
      Lock_Generic (L.RTS'Access);
   end Write_Lock;

   procedure Write_Lock (L : not null access System.OS_Locks.RTS_Lock) is
   begin
      Lock_Generic (L);
   end Write_Lock;

   procedure Write_Lock (T : ST.Task_Id) is
   begin
      Lock_Generic (T.Common.LL.L'Access);
   end Write_Lock;

   ---------------
   -- Read_Lock --
   ---------------

   procedure Read_Lock
     (L : not null access Lock; Ceiling_Violation : out Boolean) is
   begin
      Write_Lock (L, Ceiling_Violation);
   end Read_Lock;

   ------------
   -- Unlock --
   ------------

   procedure Unlock (L : not null access Lock) is
   begin
      Unlock_Generic (L.RTS'Access);
   end Unlock;

   procedure Unlock (L : not null access System.OS_Locks.RTS_Lock) is
   begin
      Unlock_Generic (L);
   end Unlock;

   procedure Unlock (T : ST.Task_Id) is
   begin
      Unlock_Generic (T.Common.LL.L'Access);
   end Unlock;

   --------------
   -- Lock_RTS --
   --------------

   procedure Lock_RTS is
   begin
      Lock_Generic (Single_RTS_Lock'Access);
   end Lock_RTS;

   procedure Unlock_RTS is
   begin
      Unlock_Generic (Single_RTS_Lock'Access);
   end Unlock_RTS;

   -----------------
   -- Set_Ceiling --
   -----------------

   procedure Set_Ceiling
     (L : not null access Lock; Prio : System.Any_Priority) is
   begin
      L.RTS.Ceiling := Prio;
   end Set_Ceiling;

   -----------
   -- Yield --
   -----------

   procedure Yield (Do_Yield : Boolean := True) is
   begin
      --  FIFO_Within_Priorities, no time slicing: yielding has no effect
      --  beyond what the scheduler already does on priority change.
      null;
   end Yield;

   ------------------
   -- Set_Priority --
   ------------------

   procedure Set_Priority
     (T : ST.Task_Id; Prio : System.Any_Priority;
      Loss_Of_Inheritance : Boolean := False)
   is
      pragma Unreferenced (Loss_Of_Inheritance);
   begin
      pragma Assert (T = Self);
      System.OS_Interface.Set_Priority (Integer (Prio));
   end Set_Priority;

   ------------------
   -- Get_Priority --
   ------------------

   function Get_Priority (T : ST.Task_Id) return System.Any_Priority is
      P : constant Integer :=
        System.OS_Interface.Get_Priority (T.Common.LL.Thread);
   begin
      if P < Integer (System.Any_Priority'First) then
         return System.Any_Priority'First;
      else
         return System.Any_Priority (P);
      end if;
   end Get_Priority;

   ---------------------
   -- Monotonic_Clock --
   ---------------------

   function Monotonic_Clock return Duration is
      Ticks : constant Time := Time (System.OS_Interface.Clock);
      Whole : constant Time := Ticks / Freq;
      Frac  : constant Time := Ticks mod Freq;
   begin
      return Duration (Whole) + Duration (Frac) / Integer (Freq);
   end Monotonic_Clock;

   -------------------
   -- RT_Resolution --
   -------------------

   function RT_Resolution return Duration is
   begin
      return Duration (1.0) / Integer (Freq);
   end RT_Resolution;

   -----------
   -- Sleep --
   -----------

   procedure Sleep
     (Self_ID : ST.Task_Id; Reason : System.Tasking.Task_States)
   is
      pragma Unreferenced (Reason);
   begin
      --  Bring up the slave CPUs the first time any task blocks (in practice the
      --  environment task's first wait -- the activation of the first tasks).  A
      --  task pinned to another core is created+enqueued during elaboration
      --  while the slaves are still stopped (so the cross-core Insert is valid),
      --  but the binder only starts the slaves at the END of adainit -- which is
      --  unreachable while the env is blocked here waiting for that task to
      --  activate.  Starting them now lets the slave pick up the enqueued task
      --  and complete its activation.  Idempotent (guarded); the binder's
      --  end-of-adainit Start_Slave_CPUs then no-ops.
      System.BB.CPU_Primitives.Multiprocessors.Start_All_CPUs;

      pragma Assert (Self_ID = Self);
      --  Sleep is called with Self_ID's ATCB lock held (the GNULL contract).
      --  Fully release it -- the priority ceiling AND the Fair_Lock -- across
      --  the suspension and re-acquire on wakeup, matching the hosted runtime's
      --  atomic condition-variable wait.  Releasing the ceiling drops us to our
      --  base priority so that waking us does not preempt the waker (which
      --  still holds our ATCB lock); releasing the Fair_Lock lets the waker take
      --  it.  The BB kernel's Wakeup_Signaled flag closes the wakeup race.
      Unlock_Generic (Self_ID.Common.LL.L'Access);
      System.OS_Interface.Sleep;
      Lock_Generic (Self_ID.Common.LL.L'Access);
   end Sleep;

   ----------------
   -- Timed_Sleep --
   ----------------

   procedure Timed_Sleep
     (Self_ID  : ST.Task_Id;
      Time     : Duration;
      Mode     : ST.Delay_Modes;
      Reason   : System.Tasking.Task_States;
      Timedout : out Boolean;
      Yielded  : out Boolean)
   is
      pragma Unreferenced (Reason);
      Abs_Secs : constant Duration :=
        (if Mode = Relative_Mode then Monotonic_Clock + Time else Time);
      Ticks : constant OSI.Time :=
        OSI.Time (Long_Long_Integer (Abs_Secs * Duration (Integer (Freq))))
        --  Absolute_Calendar (mode 1) deadlines are expressed in the Ada.Calendar
        --  time base, which is zeroed at RTS init (Ada.Calendar.Clock reads
        --  System.BB.Time.Clock - Epoch).  Delay_Until compares against the RAW
        --  counter, so shift a Calendar deadline back into the raw base by adding
        --  Epoch.  Relative and Absolute_RT deadlines are already raw-based.
        + (if Mode = Absolute_Calendar_Mode then System.BB.Time.Epoch else 0);
   begin
      --  The Duration->ticks multiply is no longer masked: the resume-path SAR
      --  fix (highint5.S / context_switch.S) keeps a preempted divide from
      --  tearing, so the brief Enter_Kernel here was redundant.
      --  Called with Self_ID's ATCB lock held (see Sleep); fully release it
      --  across the timed suspension and re-acquire on wakeup.
      Self_ID.Common.State := ST.Delay_Sleep;
      Unlock_Generic (Self_ID.Common.LL.L'Access);
      System.OS_Interface.Delay_Until (Ticks);
      Lock_Generic (Self_ID.Common.LL.L'Access);
      Self_ID.Common.State := ST.Runnable;
      Timedout := True;
      Yielded  := True;
   end Timed_Sleep;

   ----------------
   -- Timed_Delay --
   ----------------

   procedure Timed_Delay
     (Self_ID : ST.Task_Id; Time : Duration; Mode : ST.Delay_Modes)
   is
      Abs_Secs : constant Duration :=
        (if Mode = Relative_Mode then Monotonic_Clock + Time else Time);
      Ticks : constant OSI.Time :=
        OSI.Time (Long_Long_Integer (Abs_Secs * Duration (Integer (Freq))));
   begin
      --  No interrupt mask needed: the resume-path SAR fix keeps a preempted
      --  Duration->ticks divide from tearing.  Reached only via the relative
      --  soft-link path; absolute delays use Delay_Until (no multiply).
      Self_ID.Common.State := ST.Delay_Sleep;
      System.OS_Interface.Delay_Until (Ticks);
      Self_ID.Common.State := ST.Runnable;
   end Timed_Delay;

   -----------------
   -- Delay_Until --
   -----------------

   procedure Delay_Until (Self_ID : ST.Task_Id; Abs_Time : Time) is
   begin
      --  Absolute delay with NO Duration->ticks conversion: Abs_Time is
      --  already in ticks, so there is no multiply to tear.  Common.State is
      --  preserved (the abort-wakeup path reads Delay_Sleep).  The a-retide
      --  caller holds no ATCB lock and has masked interrupts;
      --  OS_Interface.Delay_Until's Leave_Kernel re-balances.
      Self_ID.Common.State := ST.Delay_Sleep;
      System.OS_Interface.Delay_Until (Abs_Time);
      Self_ID.Common.State := ST.Runnable;
   end Delay_Until;

   ------------
   -- Wakeup --
   ------------

   procedure Wakeup
     (T : ST.Task_Id; Reason : System.Tasking.Task_States)
   is
      pragma Unreferenced (Reason);
   begin
      --  A task blocked in `delay` is BB-Delayed (parked in the per-CPU alarm
      --  queue), which the generic BB Wakeup cannot wake -- it only knows
      --  Suspended/Runnable, so it would just set Wakeup_Signaled and leave the
      --  task delaying until its natural expiry.  This is the wake the abort
      --  flow uses for a `delay`-blocked target (Locked_Abort_To_Level on
      --  Delay_Sleep), so prompt delay-abort depends on it.  Cancel_Delay
      --  unlinks the alarm and makes the task Runnable now (cross-core via a
      --  Poke) and returns True; it returns False for a non-Delayed task, in
      --  which case the ordinary Wakeup is correct (entry waiters, etc.).
      if not System.OS_Interface.Cancel_Delay (T.Common.LL.Thread) then
         System.OS_Interface.Wakeup (T.Common.LL.Thread);
      end if;
   end Wakeup;

   ----------------
   -- Enter_Task --
   ----------------

   procedure Enter_Task (Self_ID : ST.Task_Id) is
   begin
      Self_ID.Common.LL.Lwp := Lwp_Self;
      System.Tasking.Debug.Task_Creation_Hook (Self_ID.Common.LL.Thread);
      System.OS_Interface.Set_Priority
        (Integer (Self_ID.Common.Base_Priority));
      if Arm_Stack_Watchpoint_Hook'Address /= Null_Address then
         Arm_Stack_Watchpoint_Hook;
      end if;
   end Enter_Task;

   --------------------------
   -- Stack_Overflow_Raise --
   --------------------------

   --  Recoverable stack-overflow, stage 2: called (via call4) from the
   --  xt_debugexception trampoline when the stack-limit watchpoint fires.  It
   --  raises Storage_Error in the faulting task; the ZCX unwinder propagates it
   --  to a `when Storage_Error` handler (or terminates the task if none).  Runs
   --  in the redzone headroom below the watchpoint.
   procedure Stack_Overflow_Raise;
   pragma Export (C, Stack_Overflow_Raise, "__gnat_stack_overflow_raise");

   procedure Stack_Overflow_Raise is
   begin
      raise Storage_Error;
   end Stack_Overflow_Raise;

   ---------------
   -- Exit_Task --
   ---------------

   procedure Exit_Task is
   begin
      --  The task body has completed.  __gnat_start_thread reaches the task
      --  wrapper with a `callx4` and does NOT expect it to return (there is no
      --  instruction after the call), so Exit_Task must never return: park the
      --  calling thread permanently.  System.OS_Interface.Sleep removes it from
      --  the ready queue and switches to another task; it is never woken, so
      --  this loop does not return.  (The ATCB/stack of a declared task are
      --  reclaimed with its enclosing frame; `new` task objects via Free_ATCB.)
      loop
         System.OS_Interface.Sleep;
      end loop;
   end Exit_Task;

   --------------------
   -- ATCB_Allocation --
   --------------------

   package body ATCB_Allocation is

      function New_ATCB (Entry_Num : ST.Task_Entry_Index) return ST.Task_Id is
         type ATCB_Access is access ST.Ada_Task_Control_Block;
         function To_Id is new
           Ada.Unchecked_Conversion (ATCB_Access, ST.Task_Id);
      begin
         return To_Id (new ST.Ada_Task_Control_Block (Entry_Num));
      end New_ATCB;

      procedure Free_ATCB (T : ST.Task_Id) is
         type ATCB_Access is access all ST.Ada_Task_Control_Block;
         function To_Acc is new
           Ada.Unchecked_Conversion (ST.Task_Id, ATCB_Access);
         procedure Free is new Ada.Unchecked_Deallocation
           (ST.Ada_Task_Control_Block, ATCB_Access);
         X : ATCB_Access := To_Acc (T);
      begin
         Free (X);
      end Free_ATCB;

   end ATCB_Allocation;

   --------------------
   -- Initialize_TCB --
   --------------------

   procedure Initialize_TCB (Self_ID : ST.Task_Id; Succeeded : out Boolean) is
   begin
      if Multiprocessor then
         Fair_Locks.Initialize (Self_ID.Common.LL.L.L);
      end if;
      Self_ID.Common.LL.L.Ceiling := System.Any_Priority'Last;
      Succeeded := True;
   end Initialize_TCB;

   ------------------
   -- Finalize_TCB --
   ------------------

   procedure Finalize_TCB (T : ST.Task_Id) is
      use type System.OS_Interface.Thread_Id;
   begin
      --  Return the primary stack to the heap if WE allocated it (Create_Task
      --  case 3).  A preallocated / frame stack has Owned_Stack = Null and is
      --  left alone.  The hook waits until the terminating thread has switched
      --  off this stack (it is no longer the running thread on any CPU) before
      --  releasing it, so this is safe even though the GNARL may reach here
      --  while the task is still on its way into Exit_Task's Sleep.
      if T.Common.LL.Owned_Stack /= Null_Address
        and then Stack_Free_Hook'Address /= Null_Address
        and then T.Common.LL.Thread /= System.OS_Interface.Null_Thread_Id
      then
         Stack_Free_Hook (T.Common.LL.Owned_Stack, T.Common.LL.Thread.all'Address);
         T.Common.LL.Owned_Stack := Null_Address;
      end if;

      --  Do NOT free the ATCB here: a declared task's ATCB lives in its
      --  enclosing frame, so freeing it would corrupt the stack.  Dynamically
      --  allocated ATCBs (`new` task objects) are released by the GNARL via
      --  ATCB_Allocation.Free_ATCB.
   end Finalize_TCB;

   ----------------
   -- Abort_Task --
   ----------------

   procedure Abort_Task (T : ST.Task_Id) is
      --  `abort` IS delivered on this port: System.Parameters.No_Abort is
      --  forced False (gen_runtime.sh patches s-parame), so an aborted task
      --  raises Abort_Signal at its next completion point (delay, entry call,
      --  Undefer_Abort) and terminates cleanly.
      --
      --  If the target is blocked in a `delay`, wake it so abort takes effect
      --  PROMPTLY instead of at the delay's natural expiry -- the same
      --  Cancel_Delay routing as Wakeup (same-core unlink, cross-core Poke).
      --  It is a no-op for a task parked on a protected entry (Suspended) or
      --  spinning in a CPU loop (Runnable): those still abort when they next
      --  reach a completion point (no crash); force-waking a Suspended entry
      --  task would drive an entry-cancel path not yet built.
      Woken : constant Boolean :=
        System.OS_Interface.Cancel_Delay (T.Common.LL.Thread);
      pragma Unreferenced (Woken);
   begin
      null;
   end Abort_Task;

   -----------------
   -- Create_Task --
   -----------------

   procedure Create_Task
     (T          : ST.Task_Id;
      Wrapper    : System.Address;
      Stack_Size : System.Parameters.Size_Type;
      Priority   : System.Any_Priority;
      Succeeded  : out Boolean)
   is
      SI  : System.Stack_Checking.Stack_Info renames
              T.Common.Compiler_Data.Pri_Stack_Info;
      Low : System.Address;
   begin
      --  Bottom (low) address of the task's primary stack.  s-bbthre derives
      --  the (descending) stack top as Low + Stack_Size.  With preallocated
      --  stacks the compiler fills SI; the full runtime instead allocates the
      --  stack dynamically, so do that here when SI is empty.
      if SI.Limit /= Null_Address then
         Low := SI.Limit;
         T.Common.LL.Owned_Stack := Null_Address;   --  preallocated, not ours
      elsif SI.Base /= Null_Address then
         Low := SI.Base;
         T.Common.LL.Owned_Stack := Null_Address;   --  preallocated, not ours
      else
         Low := Alloc_Task_Stack (Stack_Size);
         SI.Limit := Low;
         SI.Base  := Low + Storage_Offset (Stack_Size);
         SI.Size  := Storage_Offset (Stack_Size);
         T.Common.LL.Owned_Stack := Low;            --  ours -> free on finalize
      end if;

      --  Heap-exhaustion guard.  If Alloc_Task_Stack could not satisfy the
      --  request, Low is null.  Proceeding would base the task stack at address
      --  0 (SP = Stack_Size) and SILENTLY CORRUPT -- the task wild-jumps on its
      --  first window spill (this was the CXD4009 "corruption").  Instead fail
      --  the creation so Activate_Tasks raises Tasking_Error: a clean,
      --  diagnosable error rather than a crash.
      if Low = Null_Address then
         T.Common.LL.Owned_Stack := Null_Address;
         Succeeded := False;
         return;
      end if;

      T.Common.LL.Thread := T.Common.LL.Thread_Desc'Access;

      System.OS_Interface.Thread_Create
        (T.Common.LL.Thread,
         Wrapper,
         To_Address (T),
         Integer (Priority),
         T.Common.Base_CPU,
         Low,
         Storage_Offset (Stack_Size));

      System.OS_Interface.Set_ATCB (T.Common.LL.Thread, To_Address (T));
      Succeeded := True;
   end Create_Task;

   ----------
   -- Idle --
   ----------

   procedure Idle (Param : Address) is
      pragma Unreferenced (Param);
      T : constant Tasking.Task_Id := Self;
   begin
      --  Do Enter_Task's bookkeeping (Lwp + task-creation hook) but do NOT
      --  reset our BB scheduling priority.  The idle thread was created at
      --  Idle_Priority (= Any_Priority'First - 1 = -1) so it sits strictly
      --  below every application task.  Enter_Task would Set_Priority to this
      --  ATCB's Common.Base_Priority (= Any_Priority'First = 0, since an
      --  Any_Priority cannot represent -1), raising idle to 0 and making it
      --  TIE with a priority-'First application task; being always runnable
      --  and ahead of a freshly-woken peer in the FIFO ready queue, idle would
      --  then STARVE it (ACATS CXD4007: the lowest-priority entry caller,
      --  serviced last, never resumes, so its activator's master never
      --  completes -> deadlock).
      T.Common.LL.Lwp := Lwp_Self;
      System.Tasking.Debug.Task_Creation_Hook (T.Common.LL.Thread);
      loop
         OS_Interface.Power_Down;
      end loop;
   end Idle;

   ---------------------
   -- Initialize_Idle --
   ---------------------

   procedure Initialize_Idle (CPU_Id : CPU) is
      Success   : Boolean;
      pragma Warnings (Off, Success);
      Idle_Task : Tasking.Ada_Task_Control_Block renames Idle_Tasks (CPU_Id);
   begin
      Tasking.Initialize_ATCB
        (Self_ID          => Environment_Task_Id,
         Task_Entry_Point => Idle'Access,
         Task_Arg         => Null_Address,
         Parent           => null,
         Elaborated       => null,
         Base_Priority    => System.Any_Priority'First,
         Base_CPU         => CPU_Id,
         CPU_Is_Explicit  => True,
         Domain           => null,
         Task_Info        => System.Task_Info.Unspecified_Task_Info,
         Stack_Size       => Parameters.Size_Type (Idle_Stack_Size),
         T                => Idle_Task'Access,
         Success          => Success);

      --  Point the ATCB at the statically preallocated idle stack.
      Idle_Task.Common.Compiler_Data.Pri_Stack_Info.Base :=
        Idle_Stacks (CPU_Id)'Address;
      Idle_Task.Common.Compiler_Data.Pri_Stack_Info.Size :=
        Storage_Offset (Idle_Stack_Size);

      Idle_Task.Common.LL.Thread := Idle_Task.Common.LL.Thread_Desc'Access;
      Idle_Task.Common.State := Tasking.Runnable;
      Idle_Task.Common.Activation_Link := null;
   end Initialize_Idle;

   ----------------------
   -- Initialize_Slave --
   ----------------------

   procedure Initialize_Slave (CPU_Id : CPU) is
      Idle_Task : Tasking.Ada_Task_Control_Block renames Idle_Tasks (CPU_Id);
   begin
      Initialize_Idle (CPU_Id);
      System.OS_Interface.Initialize_Slave
        (Idle_Task.Common.LL.Thread, Idle_Priority,
         Idle_Task.Common.Compiler_Data.Pri_Stack_Info.Base,
         Idle_Task.Common.Compiler_Data.Pri_Stack_Info.Size);
      System.OS_Interface.Set_ATCB
        (Idle_Task.Common.LL.Thread, To_Address (Idle_Task'Access));
      Idle (Null_Address);
   end Initialize_Slave;

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize (Environment_Task : ST.Task_Id) is
      T : Thread_Id renames Environment_Task.Common.LL.Thread;
   begin
      T := Environment_Task.Common.LL.Thread_Desc'Access;
      Environment_Task.Common.Activation_Link := null;

      System.OS_Interface.Initialize
        (T, Environment_Task.Common.Base_Priority);
      System.OS_Interface.Set_ATCB (T, To_Address (Environment_Task));

      if Multiprocessor then
         Fair_Locks.Initialize (Single_RTS_Lock.L);
         Fair_Locks.Initialize (Environment_Task.Common.LL.L.L);
      end if;
      Single_RTS_Lock.Ceiling := System.Any_Priority'Last;
      Environment_Task.Common.LL.L.Ceiling := System.Any_Priority'Last;

      Enter_Task (Environment_Task);
      Environment_Task_Id := Environment_Task;

      for CPU_Id in CPU loop
         Idle_Stacks_Table (CPU_Id) :=
           (if System.Parameters.Stack_Grows_Down
            then (Idle_Stacks (CPU_Id)'Address + Idle_Stack_Size)
            else Idle_Stacks (CPU_Id)'Address);
      end loop;

      declare
         Idle_Task : Tasking.Ada_Task_Control_Block renames
                        Idle_Tasks (CPU'First);
      begin
         Initialize_Idle (CPU'First);
         Idle_Task.Common.LL.Thread := Idle_Task.Common.LL.Thread_Desc'Access;
         System.OS_Interface.Thread_Create
           (Idle_Task.Common.LL.Thread, Idle'Address,
            To_Address (Idle_Task'Access), Idle_Priority, CPU'First,
            Idle_Task.Common.Compiler_Data.Pri_Stack_Info.Base,
            Idle_Task.Common.Compiler_Data.Pri_Stack_Info.Size);
         System.OS_Interface.Set_ATCB
           (Idle_Task.Common.LL.Thread, To_Address (Idle_Task'Access));
      end;
   end Initialize;

   ----------------------
   -- Environment_Task --
   ----------------------

   function Environment_Task return ST.Task_Id is
   begin
      return Environment_Task_Id;
   end Environment_Task;

   -------------------
   -- Get_Thread_Id --
   -------------------

   function Get_Thread_Id (T : ST.Task_Id) return OSI.Thread_Id is
   begin
      return T.Common.LL.Thread;
   end Get_Thread_Id;

   -------------------
   -- Is_Valid_Task --
   -------------------

   function Is_Valid_Task return Boolean is
   begin
      return Self /= null;
   end Is_Valid_Task;

   -----------------------------
   -- Register_Foreign_Thread --
   -----------------------------

   function Register_Foreign_Thread return ST.Task_Id is
   begin
      return null;  --  Foreign threads are not supported on the bareboard
   end Register_Foreign_Thread;

   ----------------
   -- Stack_Guard --
   ----------------

   procedure Stack_Guard (T : ST.Task_Id; On : Boolean) is null;

   -------------
   -- Get_CPU --
   -------------

   function Get_CPU (T : ST.Task_Id) return System.Multiprocessors.CPU is
   begin
      return System.OS_Interface.Get_CPU (T.Common.LL.Thread);
   end Get_CPU;

   ------------------
   -- Get_Affinity --
   ------------------

   function Get_Affinity
     (T : ST.Task_Id) return System.Multiprocessors.CPU_Range is
   begin
      return System.OS_Interface.Get_Affinity (T.Common.LL.Thread);
   end Get_Affinity;

   -----------------------
   -- Set_Task_Affinity --
   -----------------------

   procedure Set_Task_Affinity (T : ST.Task_Id) is null;
   --  CPU is fixed at Create_Task time on the bareboard.

   ---------------------
   -- Is_Task_Context --
   ---------------------

   function Is_Task_Context return Boolean is
   begin
      return System.OS_Interface.Current_Interrupt = No_Interrupt;
   end Is_Task_Context;

   ------------------------
   -- Suspension objects --
   ------------------------

   procedure Initialize (S : in out Suspension_Object) is
   begin
      S.State   := False;
      S.Waiting := False;
      S.Waiter  := Null_Thread_Id;
      if Multiprocessor then
         Fair_Locks.Initialize (S.L);
      end if;
   end Initialize;

   procedure Finalize (S : in out Suspension_Object) is null;

   function Current_State (S : Suspension_Object) return Boolean is
   begin
      return S.State;
   end Current_State;

   procedure Set_False (S : in out Suspension_Object) is
   begin
      if Multiprocessor then
         Fair_Locks.Lock (S.L);
      end if;
      S.State := False;
      if Multiprocessor then
         Fair_Locks.Unlock (S.L);
      end if;
   end Set_False;

   procedure Set_True (S : in out Suspension_Object) is
   begin
      if Multiprocessor then
         Fair_Locks.Lock (S.L);
      end if;
      if S.Waiting then
         S.Waiting := False;
         S.State   := False;
         System.OS_Interface.Wakeup (S.Waiter);
      else
         S.State := True;
      end if;
      if Multiprocessor then
         Fair_Locks.Unlock (S.L);
      end if;
   end Set_True;

   procedure Suspend_Until_True (S : in out Suspension_Object) is
   begin
      if Multiprocessor then
         Fair_Locks.Lock (S.L);
      end if;
      if S.State then
         S.State := False;
         if Multiprocessor then
            Fair_Locks.Unlock (S.L);
         end if;
      elsif S.Waiting then
         if Multiprocessor then
            Fair_Locks.Unlock (S.L);
         end if;
         raise Program_Error;  --  Two tasks waiting: not allowed
      else
         S.Waiting := True;
         S.Waiter  := Get_Thread_Id (Self);
         if Multiprocessor then
            Fair_Locks.Unlock (S.L);
         end if;
         System.OS_Interface.Sleep;
      end if;
   end Suspend_Until_True;

   ----------------------------
   -- Abort / ATC (M5 stubs) --
   ----------------------------

   function Check_Exit (Self_ID : ST.Task_Id) return Boolean is (True);
   function Check_No_Locks (Self_ID : ST.Task_Id) return Boolean is (True);

   function Suspend_Task
     (T : ST.Task_Id; Thread_Self : OSI.Thread_Id) return Boolean is (False);
   function Resume_Task
     (T : ST.Task_Id; Thread_Self : OSI.Thread_Id) return Boolean is (False);

   procedure Stop_All_Tasks is null;
   function Stop_Task (T : ST.Task_Id) return Boolean is (False);
   function Continue_Task (T : ST.Task_Id) return Boolean is (False);

end System.Task_Primitives.Operations;
