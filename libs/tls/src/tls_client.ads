with Interfaces;
with GNAT.Sockets;

--  A TLS 1.3 client handshake over GNAT.Sockets (work in progress).  This first
--  slice does the unencrypted opening: it builds and sends a ClientHello offering
--  X25519 + AES-GCM, then receives and parses the ServerHello, recovering the
--  negotiated cipher suite and the server's X25519 key share (from which the shared
--  secret and traffic keys will be derived in the next slice).
package TLS_Client is

   subtype U8  is Interfaces.Unsigned_8;
   subtype U16 is Interfaces.Unsigned_16;
   type Byte_Array is array (Natural range <>) of U8;

   type Session is limited private;

   --  Cipher suites we offer / understand.
   TLS_AES_128_GCM_SHA256 : constant U16 := 16#1301#;
   TLS_AES_256_GCM_SHA384 : constant U16 := 16#1302#;

   --  Send ClientHello (SNI = Host), then read records until the ServerHello and
   --  parse it.  Ok is False on I/O error, a TLS alert, or an unsupported response.
   procedure Hello (S    : in out Session;
                    Sock : GNAT.Sockets.Socket_Type;
                    Host : String;
                    Ok   : out Boolean);

   --  Results available after a successful Hello.  After the ServerHello is parsed,
   --  Hello also runs the TLS 1.3 key schedule (X25519 ECDHE -> Handshake Secret ->
   --  traffic secrets), so the handshake traffic secrets and keys are available too.
   function Cipher_Suite (S : Session) return U16;
   function Server_Key_Share (S : Session) return Byte_Array;   --  32-byte X25519

   function Client_Random      (S : Session) return Byte_Array; --  32 (keylog match)
   function Server_HS_Secret   (S : Session) return Byte_Array; --  32 (server hs traffic secret)
   function Client_HS_Secret   (S : Session) return Byte_Array; --  32
   function Keys_Ready         (S : Session) return Boolean;

   --  Hello also reads + decrypts the server's encrypted handshake flight
   --  (EncryptedExtensions, Certificate, CertificateVerify, Finished) under the
   --  handshake keys.  Flight_OK means every record's AES-GCM tag authenticated and
   --  a Finished was seen -- which on its own proves the keys are right.
   function Flight_OK          (S : Session) return Boolean;
   function Have_Server_Cert   (S : Session) return Boolean;
   function Server_Cert        (S : Session) return Byte_Array; --  leaf cert DER

private
   subtype Key32 is Byte_Array (0 .. 31);

   type Session is limited record
      Priv, Pub     : Key32 := (others => 0);   --  our X25519 key pair
      Client_Random : Key32 := (others => 0);   --  our ClientHello random
      Server_Pub    : Key32 := (others => 0);   --  server's X25519 key share
      Suite         : U16   := 0;
      Have_Share    : Boolean := False;
      --  Key schedule outputs (handshake phase).
      S_HS_Secret   : Key32 := (others => 0);   --  server_handshake_traffic_secret
      C_HS_Secret   : Key32 := (others => 0);   --  client_handshake_traffic_secret
      Server_Key    : Byte_Array (0 .. 15) := (others => 0);  --  AES-128 key
      Server_IV     : Byte_Array (0 .. 11) := (others => 0);
      Have_Keys     : Boolean := False;
      --  Decrypted server flight.
      Cert_First    : Natural := 1;
      Cert_Last     : Natural := 0;
      Have_Cert     : Boolean := False;
      Flight        : Boolean := False;
   end record;
end TLS_Client;
