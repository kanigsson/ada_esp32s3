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
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SHT41;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the demo runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package SHT renames ESP32S3.SHT41;
   use type SHT.Status;

   procedure Banner;     pragma Import (C, Banner,    "native_sht_banner");
   procedure Serial (S : Interfaces.Unsigned_32; Ok : int);
                         pragma Import (C, Serial,    "native_sht_serial");
   procedure No_Device;  pragma Import (C, No_Device, "native_sht_no_device");
   procedure Sample (Temp_MC, Hum_MRH : int);
                         pragma Import (C, Sample,    "native_sht_sample");
   procedure Done;       pragma Import (C, Done,      "native_sht_done");

   Dev : SHT.Device;
   St  : SHT.Status;
   SN  : Interfaces.Unsigned_32;
begin
   delay until Clock + Milliseconds (200);   --  let the console settle
   Banner;

   SHT.Setup (Dev, Sda => 8, Scl => 7);

   --  probe: the serial number doubles as a presence check.
   SHT.Read_Serial_Number (Dev, SN, St);
   Serial (SN, Boolean'Pos (St = SHT.OK));
   if St /= SHT.OK then
      No_Device;
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
         Sample (Temp_MC => int (M.Temperature), Hum_MRH => int (M.Humidity));
      end;
   end loop;

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
