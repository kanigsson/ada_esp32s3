with Ada.Streams;
with Interfaces;

--  Pure parsing of an SNTP/NTP (RFC 4330 / 5905) reply, plus the Unix->UTC
--  calendar breakdown, factored out of the NTP_Client body so they can be proved
--  in SPARK: they touch only Interfaces / Ada.Streams scalars, never GNAT.Sockets
--  (whose controlled handles are out of subset).
--
--  Parse_Timestamp reads the transmit timestamp out of an attacker-controlled
--  reply datagram at the fixed offset (seconds in bytes 40..43) and converts it to
--  Unix time.  Every index is bounded by Last (the offset of the last received
--  byte) so a short reply fails closed, and the epoch-offset subtraction cannot
--  overflow Integer_64.  To_UTC is Howard Hinnant's civil-from-days breakdown,
--  proved AoRTE over a wide calendar window.  The socket-driving NTP_Client.Query
--  stays SPARK_Mode Off and consumes these by call.
package NTP_Parse with SPARK_Mode => On is

   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Integer_64;

   --  Seconds from 1900-01-01 (the NTP epoch) to 1970-01-01 (the Unix epoch).
   NTP_Unix : constant := 2_208_988_800;

   --  Extract the transmit timestamp (the integer seconds, bytes 40..43 of the
   --  reply) and convert it to Unix time (seconds since 1970-01-01 UTC).  Ok is
   --  False -- with Unix_Time = 0 -- on a short reply (fewer than 44 bytes) or an
   --  unsynchronised / kiss-o'-death reply (a zero timestamp).
   --
   --  Last is the offset of the last byte the socket delivered (Resp'First - 1 for
   --  an empty datagram).  The bounds preconditions -- a non-negative,
   --  datagram-sized window -- pin the offset arithmetic so no index can overflow.
   procedure Parse_Timestamp
     (Resp      : Ada.Streams.Stream_Element_Array;
      Last      : Ada.Streams.Stream_Element_Offset;
      Unix_Time : out Interfaces.Integer_64;
      Ok        : out Boolean)
     with Pre  => Resp'First >= 0
                  and then Resp'Last <= 16#FFFF#
                  and then Last >= Resp'First - 1
                  and then Last <= Resp'Last,
          Post => (if not Ok then Unix_Time = 0);

   --  Break a Unix time (seconds since 1970-01-01 UTC) into UTC calendar fields
   --  (Howard Hinnant's civil-from-days algorithm; valid for any Gregorian date).
   --  The precondition is a wide calendar window -- 0001-01-01 .. 9999-12-31 -- that
   --  comfortably contains every value Parse_Timestamp can produce (the SNTP
   --  seconds field spans only 1900..2036) and keeps the year narrowing in range.
   procedure To_UTC
     (Unix_Time : Interfaces.Integer_64;
      Year      : out Integer;
      Month     : out Integer;
      Day       : out Integer;
      Hour      : out Integer;
      Minute    : out Integer;
      Second    : out Integer)
     with Pre => Unix_Time in -62_135_596_800 .. 253_402_300_799;

end NTP_Parse;
