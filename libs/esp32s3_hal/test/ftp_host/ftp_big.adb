--  Large-transfer round-trip: STOR a 1 MiB generated file, RETR it back, and
--  verify it byte-exact -- exercising the MULTI-CHUNK send + receive paths that
--  the small ftp_host transfers don't.  Args: <ip> [port] [user] [pass].
--  Run against an upload-capable server (the bundled ftp_server.py, or pyftpdlib).
with Ada.Command_Line;  use Ada.Command_Line;
with Ada.Text_IO;       use Ada.Text_IO;
with GNAT.Sockets;
with System;
with FTP_Client;
with FTP_Test_Support;  use FTP_Test_Support;

procedure FTP_Big is
   use type FTP_Client.Status;

   function Arg (N : Positive; Default : String) return String is
     (if Argument_Count >= N then Argument (N) else Default);

   IP   : constant String := Arg (1, "127.0.0.1");
   PStr : constant String := Arg (2, "21");
   User : constant String := Arg (3, "demo");
   Pass : constant String := Arg (4, "password");
   Path : constant String := "/big.bin";

   S  : FTP_Client.Session;
   St : FTP_Client.Status;
   Sz : Natural;
   Ok : Boolean := True;

   procedure Check (Label : String; Cond : Boolean) is
   begin
      Put_Line ((if Cond then "  PASS  " else "  FAIL  ") & Label);
      if not Cond then Ok := False; end if;
   end Check;
begin
   FTP_Client.Connect
     (S, Host => GNAT.Sockets.Inet_Addr (IP), User => User, Password => Pass,
      Result => St, Port => GNAT.Sockets.Port_Type'Value (PStr), Timeout => 20.0);
   Check ("Connect / login", St = FTP_Client.OK);
   if St /= FTP_Client.OK then Set_Exit_Status (1); return; end if;

   --  STOR 1 MiB (multi-chunk send).
   Big_Reset;
   FTP_Client.Store (S, Path, Big_Source'Access, System.Null_Address, St);
   Check ("STOR 1 MiB", St = FTP_Client.OK);

   --  Server-reported size should match what we sent.
   FTP_Client.File_Size (S, Path, Sz, St);
   Check ("SIZE = 1 MiB", St = FTP_Client.OK and then Sz = Big_Bytes);

   --  RETR it back and verify byte-exact (multi-chunk receive).
   Big_Reset;
   FTP_Client.Retrieve (S, Path, Big_Verify'Access, System.Null_Address, St);
   Check ("RETR 1 MiB byte-exact",
          St = FTP_Client.OK and then Big_OK and then Big_Count = Big_Bytes);
   Put_Line ("  (" & Big_Count'Image & " bytes verified)");

   FTP_Client.Delete_File (S, Path, St);
   FTP_Client.Quit (S);

   New_Line;
   if Ok then
      Put_Line ("ftp_big: ALL PASS");
      Set_Exit_Status (0);
   else
      Put_Line ("ftp_big: FAILED");
      Set_Exit_Status (1);
   end if;
end FTP_Big;
