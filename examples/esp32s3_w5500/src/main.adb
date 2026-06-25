--  WIZnet W5500 hardwired-TCP/IP Ethernet controller bring-up on the bare-metal
--  ESP32-S3 (no FreeRTOS, no IDF).  Exercises the reusable HAL driver
--  (ESP32S3.W5500) -- the SPI transport + chip bring-up layer the socket engine
--  and a GNAT.Sockets-shaped API will be built on.
--
--  Board wiring (this board):
--     MISO = IO45   MOSI = IO4   SCLK = IO1   SCSn = IO39
--     INTn = IO3 (pull-up)       RSTn = IO11 (pull-up)
--
--    reset    pulse RSTn, then read VERSIONR (must be 0x04) as a presence check.
--    config   program a MAC + static IPv4 identity and read it back.
--    link     poll the PHY once a second and print link / speed / duplex.
--
--  Report goes through the ROM printf glue; the Ada driver does all the SPI work.
with Interfaces;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SPI;
with ESP32S3.W5500;
with ESP32S3.Log;  use ESP32S3.Log;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the demo runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package Net renames ESP32S3.W5500;
   use type Net.Link_State;
   use type Net.Phy_Speed;
   use type Net.Phy_Duplex;

   Dev : Net.Device;
   Ok  : Boolean;

   --  Print a 4-byte address as dotted decimal.
   procedure Put_IP (A : Net.IPv4_Address) is
   begin
      for I in A'Range loop
         Put (Integer (A (I)));
         if I < A'Last then
            Put (".");
         end if;
      end loop;
   end Put_IP;

   --  Print a 6-byte MAC as colon-separated hex.
   procedure Put_MAC (A : Net.MAC_Address) is
   begin
      for I in A'Range loop
         Put_Hex (Interfaces.Unsigned_32 (A (I)), 2);
         if I < A'Last then
            Put (":");
         end if;
      end loop;
   end Put_MAC;

   --  This board's identity (edit to taste).
   My_MAC     : constant Net.MAC_Address  := (16#00#, 16#08#, 16#DC#,
                                              16#01#, 16#02#, 16#03#);
   My_IP      : constant Net.IPv4_Address := Net.IPv4 (192, 168, 1, 50);
   My_Subnet  : constant Net.IPv4_Address := Net.IPv4 (255, 255, 255, 0);
   My_Gateway : constant Net.IPv4_Address := Net.IPv4 (192, 168, 1, 1);
begin
   delay until Clock + Milliseconds (200);   --  let the console settle
   Put_Line ("[w5500] WIZnet W5500 bring-up (MISO=45 MOSI=4 SCLK=1 CS=39 RST=11)");

   Net.Setup (Dev, Sclk => 1, Mosi => 4, Miso => 45, Cs => 39,
              Rst => 11, Int => 3, Host => ESP32S3.SPI.SPI2,
              Clock_Hz => 10_000_000);

   --  Reset and identify.
   Net.Reset (Dev, Ok);
   Put ("[w5500] VERSIONR = 0x");
   Put_Hex (Interfaces.Unsigned_32 (Net.Version (Dev)), 2);
   Put ("  ");
   Put_Line (if Ok then "(W5500 present)" else "(unexpected -- check wiring/power!)");
   if not Ok then
      loop
         delay until Clock + Seconds (3600);
      end loop;
   end if;

   --  Program identity and read it back.
   Net.Configure (Dev, MAC => My_MAC, IP => My_IP,
                  Subnet => My_Subnet, Gateway => My_Gateway);
   Put ("[w5500] MAC = ");  Put_MAC (Net.Get_MAC (Dev));  New_Line;
   Put ("[w5500] IP  = ");  Put_IP  (Net.Get_IP (Dev));   New_Line;

   --  Poll the PHY link once a second.
   loop
      declare
         P : constant Net.Phy_Status := Net.Phy (Dev);
      begin
         Put ("[w5500] link ");
         if P.Link = Net.Up then
            Put ("UP   ");
            Put (if P.Speed = Net.Mbps_100 then "100Mbps " else "10Mbps  ");
            Put_Line (if P.Duplex = Net.Full then "full-duplex" else "half-duplex");
         else
            Put_Line ("DOWN  (no cable / no link partner)");
         end if;
      end;
      delay until Clock + Seconds (1);
   end loop;
end Main;
