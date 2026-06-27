--  What it demonstrates
--  ---------------------
--  A REAL-WORLD FTP client run over the W5500: it logs in anonymously to the
--  public Tele2 speedtest FTP server (speedtest.tele2.net, vsftpd), prints a test
--  file's SIZE, downloads it (RETR, counting bytes -- it's a binary .zip),
--  uploads a small file to /upload (auto-deleted by the server), lists the root,
--  and quits.  The FTP analogue of esp32s3_tls_weather: same static-IP + DNS
--  bring-up, but plain FTP instead of HTTPS.  Passive mode, binary.
--
--  Build & run
--  -----------
--    ./x run esp32s3_ftp_tele2
--  build.sh sets the embedded runtime profile (ESP32S3_RTS_PROFILE=embedded).
--
--  Network
--  -------
--  The board takes the static IP 192.168.1.50 (/24); set the gateway in
--  w5500_dev.adb to YOUR LAN's internet gateway, and make sure outbound FTP
--  (port 21, passive) is permitted on your network.  Host name resolution uses
--  public DNS (8.8.8.8).
--
--  Expected output (abridged)
--  --------------------------
--    [ftp] real-world FTP client -> speedtest.tele2.net (anonymous)
--    [w5500] link up, IP 192.168.1.50
--    [ftp] resolving speedtest.tele2.net ...
--    [ftp] speedtest.tele2.net = 90.130.70.73
--    [ftp] logged in.
--    [ftp] SIZE /1KB.zip = 1024 bytes
--    [ftp] RETR /1KB.zip: 1024 bytes received, result OK
--    [ftp] STOR /upload/esp32s3_ftp_test.bin (256 bytes): OK
--    [ftp] --- NLST / ---
--    1KB.zip
--    1MB.zip
--    ...
--    [ftp] done.
with Ada.Real_Time; use Ada.Real_Time;
with GNAT.Sockets;  use GNAT.Sockets;
with ESP32S3.Log;   use ESP32S3.Log;
with W5500_Dev;
with DNS_Client;
with FTP_Client;
with FTP_Sinks;
with System;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   use type FTP_Client.Status;

   Host       : constant String         := "speedtest.tele2.net";
   DNS_Server : constant Inet_Addr_Type  := Inet_Addr ("8.8.8.8");   --  public DNS
   FTP_Port   : constant Port_Type       := 21;
   User       : constant String          := "anonymous";
   Pass       : constant String          := "esp32s3@example.com";
   Get_Path   : constant String          := "/1KB.zip";
   Put_Path   : constant String          := "/upload/esp32s3_ftp_test.bin";

   Lookup_Timeout : constant Duration := 5.0;
   Op_Timeout     : constant Duration := 15.0;
   Park           : constant Time_Span := Seconds (3600);

   Server_IP : Inet_Addr_Type;
   S         : FTP_Client.Session;
   St        : FTP_Client.Status;
   Sz        : Natural;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[ftp] real-world FTP client -> " & Host & " (anonymous)");

   if not W5500_Dev.Bring_Up then
      loop
         delay until Clock + Park;
      end loop;
   end if;

   Put_Line ("[ftp] resolving " & Host & " ...");
   if not DNS_Client.Resolve (DNS_Server, Host, Server_IP, Timeout => Lookup_Timeout)
   then
      Put_Line ("[ftp] DNS resolution failed");
      loop
         delay until Clock + Park;
      end loop;
   end if;
   Put_Line ("[ftp] " & Host & " = " & Image (Server_IP));

   FTP_Client.Connect
     (S, Host => Server_IP, User => User, Password => Pass,
      Result => St, Port => FTP_Port, Timeout => Op_Timeout);
   if St /= FTP_Client.OK then
      Put ("[ftp] connect/login failed: ");
      Put_Line (St'Image);
      loop
         delay until Clock + Park;
      end loop;
   end if;
   Put_Line ("[ftp] logged in.");

   --  SIZE + download a small binary test file (count bytes; it is a .zip).
   FTP_Client.File_Size (S, Get_Path, Sz, St);
   if St = FTP_Client.OK then
      Put ("[ftp] SIZE " & Get_Path & " = ");
      Put (Sz);
      Put_Line (" bytes");
   end if;

   FTP_Sinks.Reset_Count;
   FTP_Client.Retrieve
     (S, Get_Path, FTP_Sinks.Count_Chunk'Access, System.Null_Address, St);
   Put ("[ftp] RETR " & Get_Path & ": ");
   Put (FTP_Sinks.Bytes_Seen);
   Put (" bytes received, result ");
   Put_Line (St'Image);

   --  Upload a small test file to /upload (the server auto-deletes it).
   FTP_Sinks.Reset_Source;
   FTP_Client.Store
     (S, Put_Path, FTP_Sinks.Test_Source'Access, System.Null_Address, St);
   Put ("[ftp] STOR " & Put_Path & " (");
   Put (FTP_Sinks.Upload_Bytes);
   Put (" bytes): ");
   Put_Line (St'Image);

   --  List the root directory (the test files).
   Put_Line ("[ftp] --- NLST / ---");
   FTP_Client.List
     (S, FTP_Sinks.Put_Chunk'Access, System.Null_Address, St, Path => "/");
   New_Line;
   Put ("[ftp] list result: ");
   Put_Line (St'Image);

   FTP_Client.Quit (S);
   Put_Line ("[ftp] done.");

   loop
      delay until Clock + Park;
   end loop;
end Main;
