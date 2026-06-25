--  DHCP client on the W5500: get an IP automatically instead of a static address.
--
--  Brings the chip up, then runs ESP32S3.W5500.DHCP.Acquire_Lease (the DORA
--  handshake over UDP) and prints the leased IP / subnet / gateway / DNS.  After
--  this the chip is configured with the leased address, so the higher layers
--  (the socket engine, GNAT.Sockets) are ready to use.
with Interfaces;    use Interfaces;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SPI;
with ESP32S3.W5500;
with ESP32S3.W5500.DHCP;
with ESP32S3.Log;   use ESP32S3.Log;
with Net_Dev;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package Net  renames ESP32S3.W5500;
   package DHCP renames ESP32S3.W5500.DHCP;
   use type Net.Link_State;

   Dev : Net.Device renames Net_Dev.Dev;
   Ok  : Boolean;

   MAC   : constant Net.MAC_Address := (16#00#, 16#08#, 16#DC#, 16#01#, 16#02#, 16#03#);
   Lease : DHCP.Lease_Info;

   procedure Put_IP (A : Net.IPv4_Address) is
   begin
      for I in A'Range loop
         Put (Integer (A (I)));
         if I < A'Last then Put ("."); end if;
      end loop;
   end Put_IP;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[dhcp] W5500 DHCP client");

   Net.Setup (Dev, Sclk => 1, Mosi => 4, Miso => 45, Cs => 39,
              Rst => 11, Int => 3, Host => ESP32S3.SPI.SPI2,
              Clock_Hz => 10_000_000);
   Net.Reset (Dev, Ok);
   if not Ok then
      Put_Line ("[dhcp] W5500 not found -- check wiring");
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   for Try in 1 .. 40 loop                      --  PHY auto-neg takes ~secs
      exit when Net.Link (Dev) = Net.Up;
      delay until Clock + Milliseconds (250);
   end loop;
   Put_Line (if Net.Link (Dev) = Net.Up then "[dhcp] link up" else "[dhcp] link down");

   Put_Line ("[dhcp] requesting a lease (DORA) ...");
   if DHCP.Acquire_Lease (Dev'Access, MAC, Lease) then
      Put ("[dhcp] IP      = ");  Put_IP (Lease.IP);       New_Line;
      Put ("[dhcp] subnet  = ");  Put_IP (Lease.Subnet);   New_Line;
      Put ("[dhcp] gateway = ");  Put_IP (Lease.Gateway);  New_Line;
      Put ("[dhcp] DNS     = ");  Put_IP (Lease.DNS);      New_Line;
      Put ("[dhcp] lease   = ");  Put (Integer (Lease.Lease_Seconds));  Put_Line (" s");
   else
      Put_Line ("[dhcp] no lease -- no DHCP server answered");
   end if;

   loop delay until Clock + Seconds (3600); end loop;
end Main;
