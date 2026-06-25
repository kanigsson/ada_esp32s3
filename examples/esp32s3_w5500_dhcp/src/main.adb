--  DHCP client on the W5500 with automatic lease maintenance.
--
--  ESP32S3.W5500.DHCP.Maintain starts a background task that acquires an address
--  (DORA) and then keeps it: it renews (unicast) at ~T1 = 50 % of the lease,
--  rebinds (broadcast) at ~T2 = 87.5 %, and re-acquires on expiry -- reprogramming
--  the chip each time.  The On_Bound callback prints the lease on every (re)bind.
--
--  No static address: the router assigns one.  After the first bind the chip is
--  configured, so the higher layers (socket engine, GNAT.Sockets) are ready.
--
--  DHCP is necessarily chip-level, not portable GNAT.Sockets: it must run before an
--  address exists and then program the obtained IP/mask/gateway into the interface
--  -- operations below the sockets API on any platform (raw sockets + ioctl on a
--  desktop; Net.Configure here).  So this example rides ESP32S3.W5500.DHCP directly.
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SPI;
with ESP32S3.W5500;
with ESP32S3.W5500.DHCP;
with ESP32S3.Log;   use ESP32S3.Log;
with Net_Dev;
with DHCP_Print;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package Net  renames ESP32S3.W5500;
   package DHCP renames ESP32S3.W5500.DHCP;
   use type Net.Link_State;

   Dev : Net.Device renames Net_Dev.Dev;
   Ok  : Boolean;
   MAC : constant Net.MAC_Address := (16#00#, 16#08#, 16#DC#, 16#01#, 16#02#, 16#03#);
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[dhcp] W5500 DHCP client with lease maintenance");

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

   --  Start the background task: it acquires a lease (On_Bound prints it) and then
   --  renews / rebinds it automatically for as long as the program runs.
   Put_Line ("[dhcp] starting lease maintenance (acquire + auto-renew) ...");
   DHCP.Maintain (Dev'Access, MAC, On_Bound => DHCP_Print.On_Bound'Access);

   loop delay until Clock + Seconds (3600); end loop;
end Main;
