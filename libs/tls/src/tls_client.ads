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

   --  Results available after a successful Hello.
   function Cipher_Suite (S : Session) return U16;
   function Server_Key_Share (S : Session) return Byte_Array;   --  32-byte X25519

private
   subtype Key32 is Byte_Array (0 .. 31);

   type Session is limited record
      Priv, Pub   : Key32 := (others => 0);     --  our X25519 key pair
      Server_Pub  : Key32 := (others => 0);     --  server's X25519 key share
      Suite       : U16   := 0;
      Have_Share  : Boolean := False;
   end record;
end TLS_Client;
