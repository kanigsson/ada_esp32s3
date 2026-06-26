--  TLS 1.3 handshake opening over the W5500: send a ClientHello (X25519 + AES-GCM,
--  SNI), receive and parse the ServerHello.  Point Server_IP at a TLS 1.3 server,
--  e.g.  openssl s_server -tls1_3 -accept 4433 -cert c.pem -key k.pem
with Ada.Real_Time; use Ada.Real_Time;
with Interfaces;
with GNAT.Sockets;  use GNAT.Sockets;
with TLS_Client;
with X509;
with W5500_Dev;
with ESP32S3.RNG;
with ESP32S3.Log;   use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   Server_IP   : constant String    := "192.168.1.100";
   Server_Port : constant Port_Type := 4433;
   Host        : constant String    := "test.example.com";

   Sock : Socket_Type;
   S    : TLS_Client.Session;
   Ok   : Boolean;
begin
   delay until Clock + Milliseconds (200);
   ESP32S3.RNG.Enable_Entropy_Source;            --  keys need real entropy
   Put_Line ("[tls] TLS 1.3 ClientHello / ServerHello over the W5500");
   if not W5500_Dev.Bring_Up then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   Ok := False;
   begin
      Create_Socket  (Sock, Family_Inet, Socket_Stream);
      Put_Line ("[tls] connecting to " & Server_IP & ":4433 ...");
      Connect_Socket (Sock, (Family_Inet, Inet_Addr (Server_IP), Server_Port));
      TLS_Client.Hello (S, Sock, Host, Ok);
   exception
      when others =>
         Put_Line ("[tls] connection error (is the server up?)");
   end;

   if Ok then
      Put ("[tls] ServerHello: cipher suite = 0x");
      Put_Hex (Interfaces.Unsigned_32 (TLS_Client.Cipher_Suite (S)), 4);
      New_Line;
      Put ("[tls] server key share = ");
      declare
         KS : constant TLS_Client.Byte_Array := TLS_Client.Server_Key_Share (S);
      begin
         for I in 0 .. 7 loop
            Put_Hex (Interfaces.Unsigned_32 (KS (KS'First + I)), 2);
         end loop;
         Put_Line (" ...");
      end;
      Put_Line ("[tls] handshake opening OK");
      if TLS_Client.Keys_Ready (S) then
         Put ("[tls] client_random=");
         declare
            CR : constant TLS_Client.Byte_Array := TLS_Client.Client_Random (S);
         begin
            for I in CR'Range loop Put_Hex (Interfaces.Unsigned_32 (CR (I)), 2); end loop;
         end;
         New_Line;
         Put ("[tls] s_hs_secret=");
         declare
            SS : constant TLS_Client.Byte_Array := TLS_Client.Server_HS_Secret (S);
         begin
            for I in SS'Range loop Put_Hex (Interfaces.Unsigned_32 (SS (I)), 2); end loop;
         end;
         New_Line;
      end if;

      if TLS_Client.Flight_OK (S) then
         Put_Line ("[tls] encrypted handshake decrypted + authenticated (Finished seen)");
         Put_Line ("[tls] server Finished verify: "
                   & (if TLS_Client.Server_Finished_OK (S) then "OK" else "FAIL"));
         if TLS_Client.Have_Server_Cert (S) then
            declare
               DER : constant TLS_Client.Byte_Array := TLS_Client.Server_Cert (S);
               CB  : X509.Byte_Array (0 .. DER'Length - 1);
               C   : X509.Certificate;
            begin
               for I in 0 .. DER'Length - 1 loop CB (I) := DER (DER'First + I); end loop;
               X509.Parse (CB, C);
               Put ("[tls] server cert" & Natural'Image (DER'Length) & " bytes: ");
               if C.Valid then
                  Put ("parsed; host match=");
                  Put_Line (if X509.Host_Matches (CB, C, Host) then "yes" else "no");
               else
                  Put_Line ("PARSE FAIL");
               end if;
            end;
         end if;
      else
         Put_Line ("[tls] encrypted handshake decrypt FAILED");
      end if;
   else
      Put_Line ("[tls] handshake opening FAILED");
   end if;

   Close_Socket (Sock);
   loop delay until Clock + Seconds (3600); end loop;
end Main;
