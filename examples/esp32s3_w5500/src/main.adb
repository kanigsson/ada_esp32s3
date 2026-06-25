--  WIZnet W5500 TCP echo server on the bare-metal ESP32-S3 (no FreeRTOS, no IDF).
--  Exercises the reusable HAL driver (ESP32S3.W5500 transport + bring-up) and the
--  socket engine (ESP32S3.W5500.Sockets), polling-based.
--
--  Board wiring (this board):
--     MISO = IO45   MOSI = IO4   SCLK = IO1   SCSn = IO39
--     INTn = IO3 (pull-up)       RSTn = IO11 (pull-up)
--
--    reset    pulse RSTn, then read VERSIONR (must be 0x04).
--    config   program a MAC + static IPv4 (192.168.1.50) and wait for link.
--    echo     listen on TCP port 5000 and echo every byte back; loop per client.
--             Try it from a host on the same LAN:  nc 192.168.1.50 5000
--
--  Report goes through the ROM printf glue; the Ada driver does all the SPI work.
with Interfaces;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SPI;
with ESP32S3.W5500;
with ESP32S3.W5500.Sockets;
with ESP32S3.Log;  use ESP32S3.Log;
with W5500_Dev;

--  Pull the SMP slave-start entry into the link closure (glue.c calls it after
--  elaboration); core 1 just idles -- the demo runs on core 0.
with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package Net  renames ESP32S3.W5500;
   package Sock renames ESP32S3.W5500.Sockets;
   use type Sock.Status;
   use type Sock.Socket_State;
   use type Net.Link_State;

   Dev : Net.Device renames W5500_Dev.Dev;   --  the library-level, aliased W5500

   Ok          : Boolean;
   S           : Sock.Socket;
   St          : Sock.Status;
   Listen_Port : constant Sock.Port_Number := 5000;
   Buf         : Net.Byte_Array (0 .. 511);
   N, Sent     : Natural;

   procedure Put_IP (A : Net.IPv4_Address) is
   begin
      for I in A'Range loop
         Put (Integer (A (I)));
         if I < A'Last then Put ("."); end if;
      end loop;
   end Put_IP;

   My_MAC     : constant Net.MAC_Address  := (16#00#, 16#08#, 16#DC#,
                                              16#01#, 16#02#, 16#03#);
   My_IP      : constant Net.IPv4_Address := Net.IPv4 (192, 168, 1, 50);
   My_Subnet  : constant Net.IPv4_Address := Net.IPv4 (255, 255, 255, 0);
   My_Gateway : constant Net.IPv4_Address := Net.IPv4 (192, 168, 1, 1);
begin
   delay until Clock + Milliseconds (200);   --  let the console settle
   Put_Line ("[w5500] WIZnet W5500 TCP echo server (MISO=45 MOSI=4 SCLK=1 CS=39 RST=11)");

   Net.Setup (Dev, Sclk => 1, Mosi => 4, Miso => 45, Cs => 39,
              Rst => 11, Int => 3, Host => ESP32S3.SPI.SPI2,
              Clock_Hz => 10_000_000);

   Net.Reset (Dev, Ok);
   Put ("[w5500] VERSIONR = 0x");
   Put_Hex (Interfaces.Unsigned_32 (Net.Version (Dev)), 2);
   Put_Line (if Ok then "  (W5500 present)" else "  (unexpected -- check wiring!)");
   if not Ok then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   Net.Configure (Dev, MAC => My_MAC, IP => My_IP,
                  Subnet => My_Subnet, Gateway => My_Gateway);
   Put ("[w5500] IP = ");  Put_IP (Net.Get_IP (Dev));  New_Line;

   --  The PHY can take a second or two to auto-negotiate after reset; wait
   --  (bounded) for link, then proceed regardless (the W5500 stack answers
   --  ARP/ICMP independently of our socket state).
   for Try in 1 .. 20 loop
      exit when Net.Link (Dev) = Net.Up;
      delay until Clock + Milliseconds (250);
   end loop;
   Put_Line (if Net.Link (Dev) = Net.Up then "[w5500] link up" else "[w5500] link down");
   Put_Line ("[w5500] TCP echo on 192.168.1.50:5000  (try:  nc 192.168.1.50 5000)");

   --  One client at a time on hardware socket 0: listen, echo, repeat.
   loop
      Sock.Open_TCP (Dev'Access, S, Index => 0, Local_Port => Listen_Port,
                     Result => St);
      if St /= Sock.OK then
         Put_Line ("[w5500] Open_TCP failed: " & Sock.Status'Image (St));
         exit;
      end if;
      Sock.Listen (S, St);

      --  wait for a client (stay in SOCK_LISTEN until one connects)
      while Sock.State (S) = Sock.Listening loop
         delay until Clock + Milliseconds (50);
      end loop;

      if Sock.Is_Established (S) then
         Put_Line ("[w5500] client connected");
         loop
            Sock.Receive (S, Buf, N, St);
            exit when St = Sock.Closed_By_Peer;
            if N > 0 then
               Sock.Send (S, Buf (0 .. N - 1), Sent, St);   --  echo it back
            else
               delay until Clock + Milliseconds (5);        --  nothing waiting
            end if;
            exit when Sock.State (S) = Sock.Closed;
         end loop;
         Put_Line ("[w5500] client disconnected");
      end if;

      Sock.Disconnect (S);                --  graceful close, then re-listen
   end loop;

   loop delay until Clock + Seconds (3600); end loop;
end Main;
