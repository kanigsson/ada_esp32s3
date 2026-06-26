--  Pure-Ada HTTPS: fetch a live weather forecast from Open-Meteo over TLS 1.3,
--  end to end on the bare-metal ESP32-S3 with no external C TLS library.
--
--    DNS (DNS_Client) -> TCP connect :443 -> TLS 1.3 handshake (TLS_Client:
--    X25519 ECDHE, AES-128-GCM, HKDF, RSA-PSS CertificateVerify, Finished) ->
--    validate the server's certificate chain to a pinned root (ISRG Root X1,
--    Let's Encrypt) -> encrypted HTTP GET -> decrypt the JSON forecast.
--
--  All crypto is Ada (SPARKNaCl) + the ESP32-S3 accelerators.  Edit Latitude /
--  Longitude for another place.  The reference time used for certificate validity
--  is fixed here; production should take it from NTP (see esp32s3_w5500_ntp).
with Ada.Real_Time;  use Ada.Real_Time;
with Interfaces;
with GNAT.Sockets;   use GNAT.Sockets;
with TLS_Client;
with X509;
with Chain_Verify;
with Chain_Buffers;
with Trust_Anchors;
with DNS_Client;
with W5500_Dev;
with ESP32S3.RNG;
with ESP32S3.Log;    use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   Host        : constant String         := "api.open-meteo.com";
   DNS_Server  : constant Inet_Addr_Type := Inet_Addr ("8.8.8.8");
   Server_Port : constant Port_Type      := 443;
   Latitude    : constant String         := "52.52";    --  Berlin, DE
   Longitude   : constant String         := "13.41";

   CRLF : constant String := (1 => ASCII.CR, 2 => ASCII.LF);
   Req  : constant String :=
     "GET /v1/forecast?latitude=" & Latitude & "&longitude=" & Longitude
       & "&current=temperature_2m,wind_speed_10m HTTP/1.0" & CRLF
       & "Host: " & Host & CRLF & "Connection: close" & CRLF & CRLF;

   Server_IP : Inet_Addr_Type;
   Sock      : Socket_Type;
   S         : TLS_Client.Session;
   Ok        : Boolean := False;

   --  Minimal JSON scrape: the NUMERIC value following "key": within Text.  The
   --  same key also appears in the "current_units" object with a string value
   --  (e.g. "temperature_2m":"C"), so skip occurrences whose value is not a number.
   function Field (Text : String; Key : String) return String is
      I : Natural := Text'First;
   begin
      while I <= Text'Last - Key'Length + 1 loop
         if Text (I .. I + Key'Length - 1) = Key then
            declare
               First : Natural := I + Key'Length;
            begin
               while First <= Text'Last
                 and then (Text (First) = ' ' or else Text (First) = ':')
               loop
                  First := First + 1;
               end loop;
               if First <= Text'Last
                 and then (Text (First) in '0' .. '9' or else Text (First) = '-')
               then
                  declare
                     P : Natural := First;
                  begin
                     while P <= Text'Last
                       and then (Text (P) in '0' .. '9' or else Text (P) = '.'
                                 or else Text (P) = '-')
                     loop
                        P := P + 1;
                     end loop;
                     return Text (First .. P - 1);
                  end;
               end if;
               I := I + Key'Length;          --  string value: keep searching
            end;
         else
            I := I + 1;
         end if;
      end loop;
      return "";
   end Field;

begin
   delay until Clock + Milliseconds (200);
   ESP32S3.RNG.Enable_Entropy_Source;            --  keys need real entropy (CSPRNG)
   Put_Line ("[wx] pure-Ada HTTPS weather (TLS 1.3 over the W5500)");
   if not W5500_Dev.Bring_Up then
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   --  Resolve the API host by name (portable DNS_Client over GNAT.Sockets).
   Put_Line ("[wx] resolving " & Host & " ...");
   if not DNS_Client.Resolve (DNS_Server, Host, Server_IP, Timeout => 5.0) then
      Put_Line ("[wx] DNS resolution failed");
      loop delay until Clock + Seconds (3600); end loop;
   end if;
   Put_Line ("[wx] " & Host & " = " & Image (Server_IP));

   --  TLS 1.3 handshake, retried (the path to this host is intermittently flaky).
   for Attempt in 1 .. 8 loop
      begin
         Create_Socket  (Sock, Family_Inet, Socket_Stream);
         Connect_Socket (Sock, (Family_Inet, Server_IP, Server_Port));
         TLS_Client.Hello (S, Sock, Host, Ok);
      exception
         when others => Ok := False;
      end;
      exit when Ok;
      begin Close_Socket (Sock); exception when others => null; end;
      Put_Line ("[wx] handshake attempt" & Integer'Image (Attempt) & " failed; retry");
      delay until Clock + Milliseconds (800);
   end loop;

   if not Ok then
      Put_Line ("[wx] TLS handshake failed");
      loop delay until Clock + Seconds (3600); end loop;
   end if;

   Put ("[wx] TLS 1.3 up: cipher 0x");
   Put_Hex (Interfaces.Unsigned_32 (TLS_Client.Cipher_Suite (S)), 4);
   New_Line;
   Put_Line ("[wx] CertificateVerify (RSA-PSS): "
             & (if TLS_Client.Server_Cert_Verify_OK (S) then "OK" else "FAIL"));
   Put_Line ("[wx] server Finished: "
             & (if TLS_Client.Server_Finished_OK (S) then "OK" else "FAIL"));

   --  Authenticate the chain: validate the server's leaf+intermediate up to the
   --  pinned ISRG Root X1, checking each link's signature and the leaf hostname.
   declare
      use Chain_Verify;
      Now     : constant X509.Time_64 := X509.Pack_Time (2026, 6, 26, 12, 0, 0);
      Anchors : constant Cert_List :=
        (1 => (Data => Trust_Anchors.Root_DER'Access));
      R       : Result;
   begin
      Chain_Buffers.Reset;
      for I in 1 .. TLS_Client.Server_Cert_Count (S) loop
         Chain_Buffers.Add (TLS_Client.Server_Chain_Cert (S, I));
      end loop;
      R := Validate (Chain_Buffers.Chain, Anchors, Host, Now);
      Put_Line ("[wx] chain validation to ISRG Root X1:" & Natural'Image
                (TLS_Client.Server_Cert_Count (S)) & " certs -> " & Result'Image (R));
      if R /= Valid then
         Put_Line ("[wx] WARNING: chain not trusted -- aborting before sending data");
         Close_Socket (Sock);
         loop delay until Clock + Seconds (3600); end loop;
      end if;
   end;

   --  Encrypted application data: send the GET, decrypt the (possibly multi-record)
   --  response, then scrape the current temperature and wind speed from the JSON.
   declare
      Req_Bytes : TLS_Client.Byte_Array (0 .. Req'Length - 1);
      Buf       : TLS_Client.Byte_Array (0 .. 1023);
      Last      : Natural;
      R_Ok      : Boolean;
      Resp      : String (1 .. 2048);
      Resp_Len  : Natural := 0;
   begin
      for I in 0 .. Req'Length - 1 loop
         Req_Bytes (I) := Interfaces.Unsigned_8 (Character'Pos (Req (Req'First + I)));
      end loop;
      TLS_Client.Send (S, Sock, Req_Bytes);

      loop
         TLS_Client.Recv (S, Sock, Buf, Last, R_Ok);
         exit when not R_Ok;
         for I in Buf'First .. Last loop
            if Resp_Len < Resp'Last then
               Resp_Len := Resp_Len + 1;
               Resp (Resp_Len) := Character'Val (Natural (Buf (I)));
            end if;
         end loop;
      end loop;

      declare
         Temp : constant String := Field (Resp (1 .. Resp_Len), """temperature_2m""");
         Wind : constant String := Field (Resp (1 .. Resp_Len), """wind_speed_10m""");
      begin
         if Temp = "" then
            Put_Line ("[wx] could not parse the forecast (response below)");
            Put_Line (Resp (1 .. Resp_Len));
         else
            Put_Line ("[wx] forecast for " & Latitude & ", " & Longitude & " (HTTPS):");
            Put_Line ("[wx]   temperature : " & Temp & " C");
            Put_Line ("[wx]   wind speed  : " & Wind & " km/h");
         end if;
      end;
   end;

   Close_Socket (Sock);
   loop delay until Clock + Seconds (3600); end loop;
end Main;
