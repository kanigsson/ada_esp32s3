with Ada.Text_IO;  use Ada.Text_IO;
with Ada.Real_Time; use Ada.Real_Time;
with System; with System.Storage_Elements; use System.Storage_Elements;
procedure Main is
   function In_PSRAM (A : System.Address) return Boolean is
      V : constant Integer_Address := To_Integer (A);
   begin return V >= 16#3C00_0000# and then V < 16#3E00_0000#; end In_PSRAM;

   --  M4: dynamically allocated workers, awaited by their master block
   task type Worker (Id : Integer);
   task body Worker is
      Marker : Integer := Id;
   begin
      if In_PSRAM (Marker'Address) then
         Put_Line ("    [worker" & Integer'Image (Id) & " ] stack is in PSRAM");
      end if;
      for K in 1 .. 3 loop
         Put_Line ("    [worker" & Integer'Image (Id) & " ]" & Integer'Image (K));
         delay until Clock + Milliseconds (150);
      end loop;
      Put_Line ("    [worker" & Integer'Image (Id) & " ] terminating");
   end Worker;

   --  M5: a periodic task that we abort
   task Heartbeat;
   task body Heartbeat is
   begin
      loop
         Put_Line ("    [heartbeat] beat");
         delay until Clock + Milliseconds (120);
      end loop;
   end Heartbeat;
begin
   New_Line;
   Put_Line ("=== full Ada tasking: dynamic tasks (M4) + abort (M5) ===");
   declare
      type Worker_Ptr is access Worker; W1, W2 : Worker_Ptr;
   begin
      W1 := new Worker (1); W2 := new Worker (2);
      Put_Line ("[main] 2 dynamic tasks allocated; block awaits them");
   end;
   Put_Line ("[main] block exited -> both dynamic tasks terminated + freed");

   Put_Line ("[main] Heartbeat'Terminated before abort = "
             & Boolean'Image (Heartbeat'Terminated));
   abort Heartbeat;
   delay until Clock + Milliseconds (300);
   Put_Line ("[main] Heartbeat'Terminated after  abort = "
             & Boolean'Image (Heartbeat'Terminated));
   Put_Line ("[main] done.");
   loop delay until Clock + Seconds (3600); end loop;
end Main;
