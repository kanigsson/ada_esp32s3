--  HTTP GET client over the W5500, using GNAT.Sockets (TCP client).
--
--  Connects out to a web server, sends "GET / HTTP/1.0", and prints the response
--  until the server closes.  Demonstrates the TCP *client* path (Connect_Socket),
--  which the echo server (a TCP server) does not exercise.  Point Server_IP at a
--  host on your LAN running, e.g.,  python3 -m http.server 8000.
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Streams;   use Ada.Streams;
with GNAT.Sockets;  use GNAT.Sockets;
with ESP32S3.Log;   use ESP32S3.Log;
with W5500_Dev;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   Server_IP   : constant String    := "192.168.1.100";
   Server_Port : constant Port_Type := 8000;
   Path        : constant String    := "/";

   Sock  : Socket_Type;
   Buf   : Stream_Element_Array (1 .. 512);
   Last  : Stream_Element_Offset;
   SLast : Stream_Element_Offset;

   function To_SEA (S : String) return Stream_Element_Array is
      R : Stream_Element_Array (1 .. S'Length);
   begin
      for I in S'Range loop
         R (Stream_Element_Offset (I - S'First) + 1) := Character'Pos (S (I));
      end loop;
      return R;
   end To_SEA;

   procedure Put_SEA (B : Stream_Element_Array) is
   begin
      for E of B loop
         Put (Character'Val (Integer (E)));
      end loop;
   end Put_SEA;

   Request : constant String :=
     "GET " & Path & " HTTP/1.0" & ASCII.CR & ASCII.LF &
     "Host: " & Server_IP & ASCII.CR & ASCII.LF &
     "Connection: close" & ASCII.CR & ASCII.LF &
     ASCII.CR & ASCII.LF;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[http] W5500 HTTP GET client (GNAT.Sockets, TCP)");
   if not W5500_Dev.Bring_Up then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   Create_Socket  (Sock, Family_Inet, Socket_Stream);
   Put_Line ("[http] connecting to " & Server_IP & ":8000 ...");
   Connect_Socket (Sock, (Family_Inet, Inet_Addr (Server_IP), Server_Port));
   Send_Socket    (Sock, To_SEA (Request), SLast);

   Put_Line ("[http] --- response ---");
   loop
      Receive_Socket (Sock, Buf, Last);
      exit when Last < Buf'First;          --  server closed the connection
      Put_SEA (Buf (Buf'First .. Last));
   end loop;
   New_Line;
   Put_Line ("[http] --- done ---");

   Close_Socket (Sock);
   loop delay until Clock + Seconds (3600); end loop;
end Main;
