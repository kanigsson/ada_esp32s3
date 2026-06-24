--  QMI8658C 6-axis IMU driver demo on the bare-metal ESP32-S3 (no FreeRTOS, no
--  IDF).  Exercises the reusable HAL IMU driver (ESP32S3.QMI8658C) against a real
--  QMI8658C on the I2C bus:
--
--     SDA = IO8     SCL = IO7     (no INT line wired -- see Imu_Int below)
--
--  What it does, end to end on silicon:
--    probe      read WHO_AM_I (0x05); tries both SA0 addresses (0x6B, 0x6A).
--    reset      soft-reset to a known register state, then wait ~15 ms.
--    configure  set accelerometer / gyroscope full scale + output rate and
--               enable both sensors (6DOF).
--    sample     read accel + gyro + temperature once every 250 ms and print
--               them in milli-g / milli-dps / centi-degC (integer math, so the
--               ROM printf console needs no float support).
--
--  The wiring is stated here (Imu_Sda / Imu_Scl / Imu_Int) and handed to Setup;
--  the driver hard-codes no pins.  This board does not wire the QMI8658C INT
--  line, so Imu_Int is No_Pin and the demo polls.  Point Imu_Int at the GPIO an
--  INT line is wired to (INT1/INT2) to arm the data-ready interrupt instead.
--
--  Report goes through the ROM printf glue (the reliable console path here); the
--  Ada driver does all the I2C/register work.
with Interfaces;    use Interfaces;
with ESP32S3.Log;   use ESP32S3.Log;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.GPIO;
with ESP32S3.I2C;
with ESP32S3.QMI8658C;
with ESP32S3.QMI8658C.Interrupts;
with IMU_IRQ;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the demo runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package IMU renames ESP32S3.QMI8658C;
   use type IMU.Status;

   --  Board wiring for THIS example (the driver hard-codes none).  This board
   --  does not wire the QMI8658C INT line, so its pin is No_Pin and the demo
   --  polls; point it at a real GPIO to arm the data-ready interrupt instead.
   Imu_Sda : constant ESP32S3.GPIO.Pin_Id       := 8;
   Imu_Scl : constant ESP32S3.GPIO.Pin_Id       := 7;
   Imu_Int : constant ESP32S3.GPIO.Optional_Pin := ESP32S3.GPIO.No_Pin;

   --  The two possible SA0 addresses; the probe below tries each.
   Candidates : constant array (1 .. 2) of ESP32S3.I2C.Slave_Address :=
     (IMU.Address_SA0_Low, IMU.Address_SA0_High);

   --  One setup-step line, e.g. "[imu] reset     : OK" ("%-9s" left-justified).
   procedure Put_Step (Name : String; Ok : Boolean) is
   begin
      Put ("[imu] ");
      Put (Name);
      for I in Name'Length + 1 .. 9 loop
         Put (" ");
      end loop;
      Put (" : ");
      Put_Line (if Ok then "OK" else "FAIL");
   end Put_Step;

   Dev    : IMU.Device;
   St     : IMU.Status;
   Id     : Unsigned_8;
   Found  : Boolean := False;
   Addr   : ESP32S3.I2C.Slave_Address := IMU.Address_SA0_Low;

   --  Raw counts -> milli-units, in 32-bit integer math (raw * 1000 fits).
   function Mg (Raw : Integer_16; Lsb_Per_Unit : Positive) return Integer is
     (Integer (Raw) * 1000 / Lsb_Per_Unit);

   --  Integer floor(sqrt(N)) -- the accel magnitude needs no float library.
   function Isqrt (N : Integer) return Integer is
      X, Y : Integer;
   begin
      if N <= 0 then
         return 0;
      end if;
      X := N;
      Y := (X + 1) / 2;
      while Y < X loop
         X := Y;
         Y := (X + N / X) / 2;
      end loop;
      return X;
   end Isqrt;

begin
   delay until Clock + Milliseconds (200);   --  let the console settle
   Put_Line ("[imu] QMI8658C 6-axis IMU driver demo (SDA=IO8  SCL=IO7)");

   --  probe: try each SA0 address until WHO_AM_I answers 0x05.
   for I in Candidates'Range loop
      Addr := Candidates (I);
      IMU.Setup (Dev, Sda => Imu_Sda, Scl => Imu_Scl,
                 Int_Pin => Imu_Int, Address => Addr);
      IMU.Read_Who_Am_I (Dev, Id, St);
      if St = IMU.OK and then Id = IMU.Who_Am_I_Value then
         Found := True;
         exit;
      end if;
   end loop;

   Put ("[imu] who_am_i : 0x");
   Put_Hex (Unsigned_32 (Id), 2);
   Put (" @ 0x");
   Put_Hex (Unsigned_32 (Addr), 2);
   Put_Line (if Found then "  (QMI8658 present)" else "  (unexpected!)");
   if not Found then
      Put_Line ("[imu] no QMI8658C found at 0x6B or 0x6A -- check wiring/power.");
      loop
         delay until Clock + Seconds (3600);
      end loop;
   end if;

   --  Arm the INT interrupt on the stored pin -- a no-op here (Imu_Int = No_Pin).
   IMU.Interrupts.Attach (Dev, IMU_IRQ.Handler'Access);

   --  reset -> (settle) -> configure.
   IMU.Reset (Dev, St);
   Put_Step ("reset", St = IMU.OK);
   delay until Clock + Milliseconds (15);     --  reset settle time

   IMU.Configure (Dev,
                  Accel => IMU.Range_8G,
                  Gyro  => IMU.Range_512DPS,
                  Rate  => IMU.ODR_235_Hz,
                  Result => St);
   Put_Step ("configure", St = IMU.OK);
   if St /= IMU.OK then
      loop
         delay until Clock + Seconds (3600);
      end loop;
   end if;

   --  sample: read accel + gyro + temperature once a quarter second and print
   --  one line each (the glue builds the whole line and emits it with a single
   --  esp_rom_printf).
   declare
      A, G   : IMU.Axes;
      T_Raw  : Integer_16;
      A_Lsb  : constant Positive := IMU.Accel_LSB_Per_G (Dev);
      G_Lsb  : constant Positive := IMU.Gyro_LSB_Per_DPS (Dev);
   begin
      --  one temperature reading up front (its own spaced line), then stream.
      delay until Clock + Milliseconds (250);
      IMU.Read_Temperature (Dev, T_Raw, St);
      if St = IMU.OK then
         Put ("[imu] temp[C]=");
         Put_Fixed (Integer (T_Raw) * 100 / 256, 100, 2);   --  centi-degC
         New_Line;
      end if;

      delay until Clock + Milliseconds (250);
      Put_Line ("[imu] a=accel[mg]  |a|=total[m/s2]  g=gyro[mdps]");
      for Tick in 1 .. 10 loop
         delay until Clock + Milliseconds (250);

         IMU.Read_Accelerometer (Dev, A, St);
         exit when St /= IMU.OK;
         IMU.Read_Gyroscope (Dev, G, St);
         exit when St /= IMU.OK;

         declare
            Ax_Mg : constant Integer := Mg (A.X, A_Lsb);
            Ay_Mg : constant Integer := Mg (A.Y, A_Lsb);
            Az_Mg : constant Integer := Mg (A.Z, A_Lsb);
            --  |a| in milli-g, then in centi-m/s2 (1000 mg = 1 g = 9.81 m/s2).
            Mag_Mg   : constant Integer :=
              Isqrt (Ax_Mg * Ax_Mg + Ay_Mg * Ay_Mg + Az_Mg * Az_Mg);
            Mag_CMps2 : constant Integer := Mag_Mg * 981 / 1000;
         begin
            --  One compact line: a=<x><y><z>  |a|=<g.gg>  g=<x><y><z>
            Put ("[imu] a=");
            Put (Ax_Mg, Width => 6); Put (Ay_Mg, Width => 6); Put (Az_Mg, Width => 6);
            Put (" |a|=");
            Put_Fixed (Mag_CMps2, 100, 2);
            Put (" g=");
            Put (Mg (G.X, G_Lsb), Width => 7);
            Put (Mg (G.Y, G_Lsb), Width => 7);
            Put (Mg (G.Z, G_Lsb), Width => 7);
            New_Line;
         end;
      end loop;
   end;

   delay until Clock + Milliseconds (250);   --  let the last sample line drain
   Put_Line ("[imu] done.");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
