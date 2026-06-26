--  Pure-Ada TLS 1.3 client over the W5500: full handshake (X25519 ECDHE, AES-128-
--  GCM, HKDF key schedule, server CertificateVerify/Finished, our own Finished),
--  then an encrypted HTTP GET and the decrypted response.  All crypto is Ada
--  (SPARKNaCl) + the ESP32-S3 accelerators -- no external C TLS library.
--  Point Server_IP at a TLS 1.3 server, e.g. a Python ssl server or
--  openssl s_server -tls1_3 -accept 4433 -cert c.pem -key k.pem
with Ada.Real_Time; use Ada.Real_Time;
with Interfaces;
with GNAT.Sockets;  use GNAT.Sockets;
with TLS_Client;
with X509;
with Chain_Verify;
with Chain_Buffers;
with Trust_Anchors;
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
   ESP32S3.RNG.Enable_Entropy_Source;            --  keys need real entropy (CSPRNG)
   Put_Line ("[tls] pure-Ada TLS 1.3 client over the W5500");
   if not W5500_Dev.Bring_Up then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   Ok := False;
   declare
      Connected : Boolean := False;
   begin
      Put_Line ("[tls] connecting to " & Server_IP & ":4433 ...");
      for Try in 1 .. 20 loop
         begin
            Create_Socket  (Sock, Family_Inet, Socket_Stream);
            Connect_Socket (Sock, (Family_Inet, Inet_Addr (Server_IP), Server_Port));
            Connected := True;
            exit;
         exception
            when others =>
               begin Close_Socket (Sock); exception when others => null; end;
               delay until Clock + Milliseconds (700);
         end;
      end loop;
      if Connected then
         TLS_Client.Hello (S, Sock, Host, Ok);
      else
         Put_Line ("[tls] could not connect");
      end if;
   exception
      when others =>
         Put_Line ("[tls] handshake exception");
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
         Put ("[tls] c_hs_secret=");
         declare
            CS : constant TLS_Client.Byte_Array := TLS_Client.Client_HS_Secret (S);
         begin
            for I in CS'Range loop Put_Hex (Interfaces.Unsigned_32 (CS (I)), 2); end loop;
         end;
         New_Line;
      end if;

      if TLS_Client.Flight_OK (S) then
         Put_Line ("[tls] encrypted handshake decrypted + authenticated (Finished seen)");
         Put_Line ("[tls] server CertificateVerify (RSA-PSS): "
                   & (if TLS_Client.Server_Cert_Verify_OK (S) then "OK" else "FAIL"));
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

         --  Anchor the server's chain to our pinned root (Chain_Verify): every
         --  link's signature, each cert's validity at Now, and the leaf hostname.
         --  Now would come from NTP in production; here it is a fixed reference.
         if TLS_Client.Server_Cert_Count (S) >= 1 then
            declare
               use Chain_Verify;
               Now     : constant X509.Time_64 :=
                 X509.Pack_Time (2026, 6, 25, 12, 0, 0);
               Anchors : constant Cert_List :=
                 (1 => (Data => Trust_Anchors.Root_DER'Access));
               R       : Result;
            begin
               Chain_Buffers.Reset;
               for I in 1 .. TLS_Client.Server_Cert_Count (S) loop
                  Chain_Buffers.Add (TLS_Client.Server_Chain_Cert (S, I));
               end loop;
               R := Validate (Chain_Buffers.Chain, Anchors, Host, Now);
               Put_Line ("[tls] chain validation (pinned root):" & Natural'Image
                         (TLS_Client.Server_Cert_Count (S)) & " certs -> "
                         & Result'Image (R));
            end;
         end if;
      else
         Put_Line ("[tls] encrypted handshake decrypt FAILED");
      end if;

      Put_Line ("[tls] ready=" & (if TLS_Client.Ready (S) then "yes" else "no"));

      --  Encrypted application data: send an HTTP GET, decrypt the response.
      if TLS_Client.Ready (S) then
         declare
            Req : constant String :=
              "GET / HTTP/1.0" & ASCII.CR & ASCII.LF
              & "Host: " & Host & ASCII.CR & ASCII.LF
              & "Connection: close" & ASCII.CR & ASCII.LF & ASCII.CR & ASCII.LF;
            Req_Bytes : TLS_Client.Byte_Array (0 .. Req'Length - 1);
            Buf       : TLS_Client.Byte_Array (0 .. 1023);
            Last      : Natural;
            R_Ok      : Boolean;
         begin
            for I in 0 .. Req'Length - 1 loop
               Req_Bytes (I) :=
                 Interfaces.Unsigned_8 (Character'Pos (Req (Req'First + I)));
            end loop;
            TLS_Client.Send (S, Sock, Req_Bytes);
            Put_Line ("[tls] sent HTTP GET (encrypted)");
            TLS_Client.Recv (S, Sock, Buf, Last, R_Ok);
            if R_Ok then
               Put_Line ("[tls] decrypted response:");
               for I in Buf'First .. Last loop
                  Put (Character'Val (Natural (Buf (I))));
               end loop;
               New_Line;
            else
               Put_Line ("[tls] no application data (server closed / alert)");
            end if;
         end;
      end if;
   else
      Put_Line ("[tls] handshake opening FAILED");
   end if;

   Close_Socket (Sock);
   loop delay until Clock + Seconds (3600); end loop;
end Main;
