--  Real-world smoke test: drive FTP_Client against an actual public FTP server
--  (e.g. ftp.gnu.org) over the internet, using the native GNAT.Sockets backend.
--  Args: <server-ip> [port] [path] [user] [password].  Read-only ops (anonymous
--  servers don't allow upload): login, SIZE, RETR (counted), NLST.  Needs network
--  access; not a CI test.  The sink callbacks live in FTP_Test_Support.
with Ada.Command_Line;  use Ada.Command_Line;
with Ada.Text_IO;       use Ada.Text_IO;
with GNAT.Sockets;
with System;
with FTP_Client;
with FTP_Test_Support;  use FTP_Test_Support;

procedure FTP_Real is
   use type FTP_Client.Status;

   function Arg (N : Positive; Default : String) return String is
     (if Argument_Count >= N then Argument (N) else Default);

   IP   : constant String := Arg (1, "127.0.0.1");
   PStr : constant String := Arg (2, "21");
   Path : constant String := Arg (3, "/README");
   User : constant String := Arg (4, "anonymous");
   Pass : constant String := Arg (5, "esp32s3@example.com");

   S  : FTP_Client.Session;
   St : FTP_Client.Status;
   Sz : Natural;
begin
   Put_Line ("ftp_real -> " & IP & ":" & PStr & "  user=" & User & "  path=" & Path);

   FTP_Client.Connect
     (S, Host => GNAT.Sockets.Inet_Addr (IP), User => User, Password => Pass,
      Result => St, Port => GNAT.Sockets.Port_Type'Value (PStr), Timeout => 15.0);
   Put_Line ("  Connect/login : " & St'Image);
   if St /= FTP_Client.OK then
      Set_Exit_Status (1);
      return;
   end if;

   FTP_Client.File_Size (S, Path, Sz, St);
   Put_Line ("  SIZE " & Path & " : " & St'Image
             & (if St = FTP_Client.OK then Sz'Image & " bytes" else ""));

   Reset_Acc;
   FTP_Client.Retrieve (S, Path, Append_Sink'Access, System.Null_Address, St);
   Put_Line ("  RETR " & Path & " : " & St'Image
             & "," & Acc_String'Length'Image & " bytes received");

   Reset_Acc;
   FTP_Client.List (S, Append_Sink'Access, System.Null_Address, St, Path => "/");
   declare
      L : constant String  := Acc_String;
      N : constant Natural := Natural'Min (300, L'Length);
   begin
      Put_Line ("  NLST /        : " & St'Image
                & "," & L'Length'Image & " bytes of names; first few:");
      Put (L (L'First .. L'First + N - 1));
      New_Line;
   end;

   FTP_Client.Quit (S);
   Put_Line ("  Quit; Is_Open = " & FTP_Client.Is_Open (S)'Image);
end FTP_Real;
