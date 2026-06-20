------------------------------------------------------------------------------
--  GNAT RUN-TIME COMPONENTS (ESP32-S3 full)
--  S Y S T E M . O S _ L O C K S
--  S p e c
------------------------------------------------------------------------------
--  Bareboard RTS_Lock for the ESP32-S3 full-tasking runtime.  The full      --
--  GNARL takes RTS_Lock / ATCB / PO locks via Task_Primitives.Operations    --
--  (Write_Lock / Unlock / Lock_RTS).  On the bareboard SMP kernel a lock is
--  a priority ceiling (mutual exclusion on the same core, since a task at
--  the ceiling is never preempted by another task) plus a Fair_Lock spinlock
--  (mutual exclusion across cores) -- the same model System.Tasking.        --
--  Protected_Objects already uses.  The operations live in s-taprop.adb.
------------------------------------------------------------------------------

with System.Multiprocessors.Fair_Locks;

package System.OS_Locks is
   pragma Preelaborate;

   type RTS_Lock is limited record
      L               : System.Multiprocessors.Fair_Locks.Fair_Lock;
      Ceiling         : System.Any_Priority := System.Any_Priority'Last;
      Caller_Priority : System.Any_Priority := System.Any_Priority'First;
   end record;

end System.OS_Locks;
