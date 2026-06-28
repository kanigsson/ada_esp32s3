with Interfaces;

--  Pure parsing of a DHCP (RFC 2131 / 2132) reply option area, factored out of the
--  ESP32S3.W5500.DHCP body so it can be proved in SPARK: it touches only
--  Interfaces scalars / a plain Byte_Array, never the socket engine (controlled
--  handles, out of subset).
--
--  Parse_Reply walks the attacker-controlled option TLV stream of a BOOTP/DHCP
--  datagram and recovers the message type (option 53), the server id (54), the
--  subnet / gateway / DNS addresses (1 / 3 / 6), the lease time (51) and yiaddr.
--  The option lengths are *server-supplied*, so every read -- the length byte
--  RX (P + 1), the four option-value bytes reaching RX (P + 5), and the advance
--  P := P + 2 + Len -- is bounded against the count of received bytes.  A crafted
--  option near the end of the datagram can neither read past the data (the inline
--  parse's live bug) nor loop unbounded: the option is dropped and the walk ends.
--  The socket-driving ESP32S3.W5500.DHCP body stays SPARK_Mode Off and consumes
--  this by call.
package DHCP_Parse with SPARK_Mode => On is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;

   subtype Octet is Interfaces.Unsigned_8;
   type Byte_Array is array (Natural range <>) of Octet;

   --  The four bytes of an IPv4 address as carried in a DHCP address option / the
   --  yiaddr field.  Index 0 is the most significant octet.
   type Quad is array (0 .. 3) of Octet;

   --  Everything the option walk recovers from one reply.  The Have_* flags say
   --  whether the corresponding option was present and fully inside the datagram;
   --  the caller applies Subnet / Gateway / DNS / Lease_Seconds to an existing
   --  lease only when their flag is set (matching the original "update on present"
   --  behaviour).  Server_Id / Yiaddr are zeroed when absent, so the caller may
   --  copy them unconditionally.
   type Parsed_Reply is record
      Msg_Type      : Octet;                   --  option 53 (0 if absent)
      Yiaddr        : Quad;                     --  the assigned address (offset 16)
      Server_Id     : Quad;                     --  option 54
      Subnet        : Quad;                     --  option 1
      Gateway       : Quad;                     --  option 3
      DNS           : Quad;                     --  option 6
      Lease_Seconds : Interfaces.Unsigned_32;   --  option 51
      Have_Server   : Boolean;
      Have_Subnet   : Boolean;
      Have_Gateway  : Boolean;
      Have_DNS      : Boolean;
      Have_Lease    : Boolean;
   end record;

   --  Parse the DHCP reply held in RX (RX'First .. RX'First + Count - 1) and fill
   --  Result.  Count is the number of bytes the socket delivered.  The bounds
   --  preconditions -- a non-negative, datagram-sized window (a DHCP reply is at
   --  most 64 KiB; the W5500 buffer is a few hundred bytes), and Count within the
   --  buffer -- pin the offset arithmetic so no index computation can overflow.
   procedure Parse_Reply
     (RX     : Byte_Array;
      Count  : Natural;
      Result : out Parsed_Reply)
     with Pre => RX'First >= 0
                 and then RX'Last <= 16#FFFF#
                 and then Count <= RX'Length;

end DHCP_Parse;
