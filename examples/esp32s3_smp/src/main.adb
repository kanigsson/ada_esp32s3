pragma Warnings (Off);
with Ada.Real_Time; use Ada.Real_Time;
with Comm;
pragma Unreferenced (Comm);

--  Pull the SMP slave-start wrapper (__gnat_start_slave_cpus, called from
--  glue.c after elaboration) into the link closure.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

--  The environment task just idles; the cross-core Producer/Consumer (package
--  Comm) do the work on cores 1 and 0.
procedure Main is
begin
   loop
      delay until Clock + Seconds (5);
   end loop;
end Main;
