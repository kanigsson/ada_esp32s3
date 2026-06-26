--  NTP time client over the W5500, using the reusable NTP_Client module (which is
--  written entirely against GNAT.Sockets / UDP, so it is portable -- the same source
--  runs on desktop GNAT.Sockets too).  Queries a public time server and prints the
--  UTC date and time.  Edit NTP_Server below, and the IP/gateway in w5500_dev.adb.
with Interfaces;    use Interfaces;
with Ada.Real_Time; use Ada.Real_Time;
with GNAT.Sockets;  use GNAT.Sockets;
with ESP32S3.Log;   use ESP32S3.Log;
with NTP_Client;
with W5500_Dev;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   NTP_Server : constant Inet_Addr_Type := Inet_Addr ("216.239.35.0");  --  time.google.com

   Unix                : Integer_64;
   Y, Mo, D, H, Mi, Se : Integer;

   procedure Put2 (N : Integer) is   --  zero-padded two digits
   begin
      if N < 10 then Put ("0"); end if;
      Put (N);
   end Put2;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[ntp] W5500 NTP time client (NTP_Client over GNAT.Sockets)");
   if not W5500_Dev.Bring_Up then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   Put_Line ("[ntp] querying " & Image (NTP_Server) & " ...");
   if NTP_Client.Query (NTP_Server, Unix, Timeout => 5.0) then
      NTP_Client.To_UTC (Unix, Y, Mo, D, H, Mi, Se);
      Put ("[ntp] time = ");
      Put (Y); Put ("-"); Put2 (Mo); Put ("-"); Put2 (D); Put (" ");
      Put2 (H); Put (":"); Put2 (Mi); Put (":"); Put2 (Se);
      Put_Line (" UTC");
   else
      Put_Line ("[ntp] no response from the time server");
   end if;

   loop delay until Clock + Seconds (3600); end loop;
end Main;
