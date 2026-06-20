pragma Warnings (Off);
with Ada.Real_Time; use Ada.Real_Time;
with Big;

--  Pull the SMP slave-start entry (__gnat_start_slave_cpus, called from glue.c
--  after elaboration) into the link closure so core 1 is brought up.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

--  PSRAM example: the environment task fills and verifies the 1 MB PSRAM array
--  in package Big once, then idles.  See big.adb for how the array is placed in
--  external RAM, and this example's README for the configuration.
procedure Main is
begin
   Big.Run;            --  fill + verify the 1 MB PSRAM array, then idle
   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
