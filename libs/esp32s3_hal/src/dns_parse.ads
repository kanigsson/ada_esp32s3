with Ada.Streams;

--  Pure parsing of a DNS (RFC 1035) reply, factored out of the DNS_Client body
--  so it can be proved in SPARK: it touches only Ada.Streams scalars / arrays,
--  never GNAT.Sockets (whose controlled handles are out of subset).
--
--  Parse_Reply walks the attacker-controlled reply datagram and extracts the
--  first IPv4 address from an A record.  Every index into the reply is bounded
--  by RLast (the offset of the last received byte), so a hostile reply -- a label
--  run that overshoots, a compression pointer, a truncated header or a crafted
--  RDLENGTH near the end of the datagram -- can neither read out of range nor
--  loop unbounded: it fails closed (Found = False).  The socket-driving
--  DNS_Client.Resolve stays SPARK_Mode Off and consumes this by call.
package DNS_Parse with SPARK_Mode => On is

   use type Ada.Streams.Stream_Element;          --  "=" on octets in the contract
   use type Ada.Streams.Stream_Element_Offset;   --  "<="/"-" on offsets in the Pre

   subtype Octet is Ada.Streams.Stream_Element;

   --  The four bytes of an IPv4 address (h1.h2.h3.h4) as carried in the RDATA of
   --  an A record.  Index 1 is the most significant octet.
   type Host_Octets is array (1 .. 4) of Octet;

   --  Parse the DNS reply held in Resp (Resp'First .. RLast) and recover the first
   --  A-record address.  On success Found is True and Host is h1..h4; otherwise
   --  Found is False and Host is zeroed (a short / truncated / answer-free reply).
   --
   --  RLast is the offset of the last byte the socket delivered (Resp'First - 1 for
   --  an empty datagram).  The bounds preconditions -- a non-negative, DNS-message-
   --  sized window (a reply is at most 64 KiB; the W5500 buffer is 512 bytes) -- pin
   --  the offset arithmetic so no index computation can overflow.
   procedure Parse_Reply
     (Resp  : Ada.Streams.Stream_Element_Array;
      RLast : Ada.Streams.Stream_Element_Offset;
      Host  : out Host_Octets;
      Found : out Boolean)
     with Pre  => Resp'First >= 0
                  and then Resp'Last <= 16#FFFF#
                  and then RLast >= Resp'First - 1
                  and then RLast <= Resp'Last,
          Post => (if not Found then (for all K in Host'Range => Host (K) = 0));

end DNS_Parse;
