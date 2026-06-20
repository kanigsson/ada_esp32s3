pragma Warnings (Off);
with Interfaces.C;
with System;
with Ada.Real_Time;                use Ada.Real_Time;

package body Comm is

   procedure Log_Xfer (Value, From_Core, To_Core : Interfaces.C.int);
   pragma Import (C, Log_Xfer, "native_log_xfer");
   procedure Log_Rate (Gets, Posted : Interfaces.C.int);
   pragma Import (C, Log_Rate, "native_log_rate");
   function Core_Id return Interfaces.C.int;       --  PRID-derived (0 or 1)
   pragma Import (C, Core_Id, "native_core_id");

   --  Cross-core handoff via a real protected-object ENTRY.  The producer
   --  (core 1) writes the mailbox and opens the barrier; the consumer (core 0)
   --  blocks in `entry Get when Full` until served.  Serving the entry on
   --  core 1 hands the caller to core 0 through the GNARL served-entry list
   --  plus an inter-core poke (see System.Tasking.Protected_Objects.
   --  Multiprocessors).  Gets counts how many entry calls completed in a
   --  period: it stays ~1, proving the consumer truly blocks between posts
   --  rather than busy-returning.
   Gets : Integer := 0 with Atomic, Volatile;

   protected Mailbox is
      procedure Post (V, From : Integer);
      entry Get (V, From : out Integer);
   private
      Full : Boolean := False;
      Item : Integer := 0;
      Src  : Integer := 0;
   end Mailbox;

   protected body Mailbox is
      procedure Post (V, From : Integer) is
      begin
         Item := V;
         Src  := From;
         Full := True;
      end Post;
      entry Get (V, From : out Integer) when Full is
      begin
         V    := Item;
         From := Src;
         Full := False;
      end Get;
   end Mailbox;

   --  Producer on core 1: posts an incrementing value every 500 ms and reports
   --  how many consumer entry calls completed in the period (~1 == healthy).
   task Producer with Priority => System.Priority'Last - 1, CPU => 2;
   task body Producer is
      N    : Integer := 0;
      Next : Time := Clock + Milliseconds (500);
   begin
      loop
         delay until Next;
         N := N + 1;
         Log_Rate (Interfaces.C.int (Gets), Interfaces.C.int (N));
         Gets := 0;
         Mailbox.Post (N, Integer (Core_Id));     --  value + this core (1)
         Next := Next + Milliseconds (500);
      end loop;
   end Producer;

   --  Consumer on core 0: blocks in the entry until the core-1 producer posts,
   --  then reads and logs the cross-core transfer on a single line.
   task Consumer with Priority => System.Priority'Last - 1, CPU => 1;
   task body Consumer is
      V, From : Integer;
   begin
      loop
         Mailbox.Get (V, From);                   --  blocks across cores
         Gets := Gets + 1;
         Log_Xfer (Interfaces.C.int (V),
                   Interfaces.C.int (From), Core_Id);
      end loop;
   end Consumer;

end Comm;
