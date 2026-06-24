--  SHT41 temperature/humidity sensor driver demo on the bare-metal ESP32-S3 (no
--  FreeRTOS, no IDF).  Exercises the reusable HAL sensor driver (ESP32S3.SHT41)
--  against a real SHT41 on the I2C bus (SDA = IO8, SCL = IO7).  No interrupt --
--  it is simply read on request.
--
--    probe    read the 32-bit serial number (a comms check).
--    sample   trigger a high-precision measurement once a second and print the
--             temperature and relative humidity.
--
--  Report goes through the ROM printf glue; the Ada driver does all the I2C work.
with Interfaces;   use type Interfaces.Unsigned_32;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SHT41;
with ESP32S3.Log;  use ESP32S3.Log;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the demo runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package SHT renames ESP32S3.SHT41;
   use type SHT.Status;

   Dev : SHT.Device;
   St  : SHT.Status;
   SN  : Interfaces.Unsigned_32;
begin
   delay until Clock + Milliseconds (200);   --  let the console settle
   Put_Line ("[sht] SHT41 temperature/humidity driver demo (SDA=IO8 SCL=IO7)");

   SHT.Setup (Dev, Sda => 8, Scl => 7);

   --  probe: the serial number doubles as a presence check.
   SHT.Read_Serial_Number (Dev, SN, St);
   Put ("[sht] serial : 0x");
   Put_Hex (SN, 8);
   Put ("  ");
   Put_Line (if St = SHT.OK then "(SHT41 present)" else "(no ACK!)");
   if St /= SHT.OK then
      Put_Line ("[sht] no SHT41 found at 0x44 -- check wiring/power.");
      loop
         delay until Clock + Seconds (3600);
      end loop;
   end if;

   --  sample once a second.
   for Tick in 1 .. 15 loop
      delay until Clock + Seconds (1);
      declare
         M : SHT.Measurement;
      begin
         SHT.Measure (Dev, M, St);
         exit when St /= SHT.OK;
         Put ("[sht] T=");
         Put_Fixed (Integer (M.Temperature), 1000, 2);
         Put (" C  RH=");
         Put_Fixed (Integer (M.Humidity), 1000, 2);
         Put_Line (" %");
      end;
   end loop;

   Put_Line ("[sht] done.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
