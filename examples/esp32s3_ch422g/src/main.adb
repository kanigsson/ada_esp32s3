--  CH422G I2C I/O-expander driver demo on the bare-metal ESP32-S3 (no FreeRTOS,
--  no IDF).  READ-ONLY: it never drives a pin, so it cannot disturb whatever the
--  CH422G's outputs are wired to on the board.
--
--    * Setup the device on I2C0 (SDA=IO8, SCL=IO9) and Acquire it (held for the
--      whole run -- the two-level lock, like the RTC).
--    * Probe the chip (address-only ACK on the config command address 0x24).
--    * Then once a second read IO0..IO7 (RD-IO, address 0x26) and report them.
--
--  The CH422G powers up with IO0..IO7 as inputs (I/O-expansion mode), so reads
--  reflect the external pin levels without configuring anything.  (The driver's
--  Configure / Write_IO / Write_OC are available but deliberately unused here.)
with Interfaces;    use Interfaces;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.CH422G;
with ESP32S3.Log;   use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package CH renames ESP32S3.CH422G;
   use type CH.Status;

   --  Report one IO read: "0x%02x" then the eight bits IO7..IO0.
   procedure Put_Read (IO : CH.IO_Value; Ok : Boolean) is
   begin
      if not Ok then
         Put_Line ("[ch422g] read IO : bus error");
         return;
      end if;
      Put ("[ch422g] IO inputs = 0x");
      Put_Hex (Unsigned_32 (IO), 2);
      Put ("  IO7..IO0 = ");
      for B in reverse 0 .. 7 loop
         Put (Integer (Shift_Right (Unsigned_32 (IO), B) and 1));
      end loop;
      New_Line;
   end Put_Read;

   Dev : CH.Device;
   S   : CH.Session;
   V   : CH.IO_Value;
   St  : CH.Status;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[ch422g] CH422G I2C I/O expander demo (read-only)");
   Put_Line ("[ch422g]   I2C0 SDA=IO8 SCL=IO9; addrs 0x24/0x23/0x38/0x26");

   CH.Setup (Dev, Sda => 8, Scl => 9);   --  I2C0, 400 kHz
   CH.Acquire (S, Dev);

   Put ("[ch422g] probe 0x24 : ");
   Put_Line (if CH.Present (S) then "ACK (present)" else "no ACK");

   loop
      delay until Clock + Seconds (1);
      CH.Read_IO (S, V, St);
      Put_Read (V, St = CH.OK);
   end loop;
end Main;
