--  Ada task RENDEZVOUS on the bare-metal dual-core ESP32-S3
--  =========================================================
--  Runs on the `full` runtime profile (the complete GNARL tasking kernel, no
--  Jorvik restrictions), where genuine task entries / `accept` / entry calls
--  are available -- all forbidden under Ravenscar/Jorvik.
--
--  A "rendezvous" is Ada's synchronous message passing: a caller task calls a
--  server task's ENTRY and blocks; the server reaches a matching `accept`; the
--  two then execute the accept body together (the caller stays suspended), IN
--  and OUT parameters are exchanged, and both continue.
--
--  This demo builds a tiny `Calculator` server task that exports three entries
--  and serves them with a SELECTIVE ACCEPT (`select ... or accept ... end
--  select`), which waits for whichever entry is called next.  The environment
--  task (the body of `Main` -- itself an Ada task) is the client: it calls
--  `Add`, `Sub`, then `Stop`, getting each result back through an OUT parameter.
--
--  NOTE: this demo uses the environment task as the client for simplicity, but
--  a DEDICATED client task (two separately declared tasks) works fine too, as
--  does printing to the console from several tasks at once.  Both used to fault
--  ("corrupts memory during activation/handoff" / "console concurrency") -- that
--  was the ESP32-S3 W^X memory-protection feature refusing to execute the GCC
--  nested-function trampoline a frame-capturing client-task body needs.  This
--  project disables it (CONFIG_ESP_SYSTEM_MEMPROT_FEATURE=n in sdkconfig.defaults);
--  with that, dedicated-client + multi-task console output run cleanly.

with Ada.Text_IO;  use Ada.Text_IO;
with Ada.Real_Time; use Ada.Real_Time;

procedure Main is

   --  The server task and the services it offers as entries.
   task Calculator is
      entry Add (X, Y : Integer; R : out Integer);
      entry Sub (X, Y : Integer; R : out Integer);
      entry Stop;
   end Calculator;

   task body Calculator is
      Open : Boolean := True;
   begin
      Put_Line ("[calc] server ready -- waiting for a rendezvous");
      while Open loop
         --  Selective accept: block until a caller is ready on ANY entry, then
         --  serve that one.  The accept body runs with the caller suspended;
         --  the OUT parameter is delivered when the accept completes.
         select
            accept Add (X, Y : Integer; R : out Integer) do
               R := X + Y;
               Put_Line ("    [calc] Add (" & Integer'Image (X) & ","
                         & Integer'Image (Y) & " ) =>" & Integer'Image (R));
            end Add;
         or
            accept Sub (X, Y : Integer; R : out Integer) do
               R := X - Y;
               Put_Line ("    [calc] Sub (" & Integer'Image (X) & ","
                         & Integer'Image (Y) & " ) =>" & Integer'Image (R));
            end Sub;
         or
            accept Stop do
               Open := False;
            end Stop;
         end select;
      end loop;
      Put_Line ("[calc] stopped -- terminating");
   end Calculator;

   R : Integer;

begin
   New_Line;
   Put_Line ("=== Ada task rendezvous on ESP32-S3 (full tasking) ===");

   --  Let the server reach its first `accept`, then drive it with entry calls.
   delay until Clock + Milliseconds (100);

   Calculator.Add (10, 5, R);    --  entry call: blocks until accepted
   Put_Line ("[main] 10 + 5 =" & Integer'Image (R));

   Calculator.Sub (10, 5, R);
   Put_Line ("[main] 10 - 5 =" & Integer'Image (R));

   Calculator.Add (100, 23, R);
   Put_Line ("[main] 100 + 23 =" & Integer'Image (R));

   Calculator.Stop;              --  parameterless rendezvous; ends the server
   Put_Line ("[main] done.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
