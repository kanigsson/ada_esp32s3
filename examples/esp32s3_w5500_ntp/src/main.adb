--  NTP time client over the W5500, using GNAT.Sockets (UDP).
--
--  Sends a 48-byte NTP request to a public time server, reads the transmit
--  timestamp (seconds since 1900-01-01, bytes 40..43), and prints the UTC date
--  and time.  Demonstrates the UDP path (a Datagram socket + Send/Receive with a
--  destination address).  Edit NTP_Server below, and the IP/gateway in
--  w5500_dev.adb, for your LAN.
with Interfaces;    use Interfaces;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Streams;   use Ada.Streams;
with GNAT.Sockets;  use GNAT.Sockets;
with ESP32S3.Log;   use ESP32S3.Log;
with W5500_Dev;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   NTP_Server : constant String := "216.239.35.0";   --  time.google.com (IPv4)
   NTP_Unix   : constant := 2_208_988_800;            --  1900->1970 seconds offset

   Sock : Socket_Type;
   Req  : Stream_Element_Array (0 .. 47) := (0 => 16#1B#, others => 0);  --  VN=3,Mode=3
   Resp : Stream_Element_Array (0 .. 47);
   Last : Stream_Element_Offset;
   To   : aliased Sock_Addr_Type := (Family_Inet, Inet_Addr (NTP_Server), 123);
   From : aliased Sock_Addr_Type;
   Secs : Unsigned_32;

   procedure Put2 (N : Integer) is   --  zero-padded two digits
   begin
      if N < 10 then Put ("0"); end if;
      Put (N);
   end Put2;

   --  Print a Unix time as "YYYY-MM-DD HH:MM:SS UTC" (civil date from days,
   --  Howard Hinnant's algorithm).
   procedure Put_UTC (Unix : Integer_64) is
      Day : constant Integer_64 := Unix / 86_400;
      Sod : constant Integer_64 := Unix mod 86_400;
      Z   : constant Integer_64 := Day + 719_468;
      Era : constant Integer_64 := Z / 146_097;
      DOE : constant Integer_64 := Z - Era * 146_097;
      YOE : constant Integer_64 := (DOE - DOE / 1460 + DOE / 36524 - DOE / 146096) / 365;
      Yr  : constant Integer_64 := YOE + Era * 400;
      DOY : constant Integer_64 := DOE - (365 * YOE + YOE / 4 - YOE / 100);
      MP  : constant Integer_64 := (5 * DOY + 2) / 153;
      D   : constant Integer := Integer (DOY - (153 * MP + 2) / 5 + 1);
      M   : constant Integer := Integer (if MP < 10 then MP + 3 else MP - 9);
      Y   : constant Integer := Integer (if M <= 2 then Yr + 1 else Yr);
   begin
      Put (Y); Put ("-"); Put2 (M); Put ("-"); Put2 (D); Put (" ");
      Put2 (Integer (Sod / 3600)); Put (":");
      Put2 (Integer ((Sod mod 3600) / 60)); Put (":");
      Put2 (Integer (Sod mod 60));
      Put_Line (" UTC");
   end Put_UTC;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[ntp] W5500 NTP time client (GNAT.Sockets, UDP)");
   if not W5500_Dev.Bring_Up then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   Create_Socket (Sock, Family_Inet, Socket_Datagram);
   Bind_Socket   (Sock, (Family_Inet, Any_Inet_Addr, 12_345));
   Put_Line ("[ntp] querying " & NTP_Server & " ...");
   Send_Socket    (Sock, Req, Last, To => To'Access);
   Receive_Socket (Sock, Resp, Last, From => From'Access);

   if Last >= 43 then
      Secs := Shift_Left (Unsigned_32 (Resp (40)), 24)
           or Shift_Left (Unsigned_32 (Resp (41)), 16)
           or Shift_Left (Unsigned_32 (Resp (42)), 8)
           or            Unsigned_32 (Resp (43));
      Put ("[ntp] time = ");
      Put_UTC (Integer_64 (Secs) - NTP_Unix);
   else
      Put_Line ("[ntp] short or no response");
   end if;

   Close_Socket (Sock);
   loop delay until Clock + Seconds (3600); end loop;
end Main;
