with Interfaces;

--  Pure parsing of FTP (RFC 959) control-connection replies, factored out of the
--  FTP_Client body so it can be proved in SPARK: it touches only String / Natural
--  / Interfaces, never GNAT.Sockets (whose controlled handles are out of subset).
--
--  Every routine works on a reply line handed back by FTP_Client.Get_Line: the CR/
--  LF-stripped text sits in Line (Line'First .. Line'First + Last - 1), so Last is
--  the count of valid characters (0 .. Line'Length) and is the contract's only link
--  between the caller's buffer and the parse -- hence the shared Pre Last <=
--  Line'Length on every entry point.
package FTP_Replies with SPARK_Mode => On is

   use type Interfaces.Unsigned_8;    --  "=" on octets / port in the contracts
   use type Interfaces.Unsigned_16;

   subtype Octet is Interfaces.Unsigned_8;
   subtype Port_16 is Interfaces.Unsigned_16;

   --  The four bytes of an IPv4 address (h1.h2.h3.h4), as advertised by a PASV
   --  reply.  Index 1 is the most significant octet.
   type Host_Octets is array (1 .. 4) of Octet;

   --  The 3-digit reply code at the start of Line, or -1 if the first three
   --  characters are not all digits (or the line is too short).
   function Code_Of (Line : String; Last : Natural) return Integer
     with Pre  => Last <= Line'Length,
          Post => Code_Of'Result = -1 or else Code_Of'Result in 0 .. 999;

   --  A reply line "NNN-" opens a multi-line reply (RFC 959 4.2): the dash after
   --  the code means more lines follow, ending at the next "NNN " (same code).
   function Is_Mid_Multiline (Line : String; Last : Natural) return Boolean
     with Pre => Last <= Line'Length;

   --  Does Line close a multi-line reply opened with code Code?  I.e. it carries
   --  that code followed by a space (or is too short to carry a continuation dash).
   function Is_Final_Line (Line : String; Last, Code : Natural) return Boolean
     with Pre => Last <= Line'Length;

   --  Parse a PASV "227 ... (h1,h2,h3,h4,p1,p2)" reply.  On success Ok is True,
   --  Host is h1..h4 and Port is p1 * 256 + p2; otherwise Ok is False and Host/Port
   --  are zeroed.  A field that overflows an octet (> 255), a missing field, or no
   --  parenthesised group all fail closed -- so a hostile reply can neither index
   --  out of range nor overflow the port (the bug the inline parse carried).
   procedure Parse_Pasv (Line : String;
                         Last : Natural;
                         Host : out Host_Octets;
                         Port : out Port_16;
                         Ok   : out Boolean)
     with Pre  => Last <= Line'Length and then Line'Last < Integer'Last,
          Post => (if not Ok then
                     Port = 0
                     and then (for all K in Host'Range => Host (K) = 0));

end FTP_Replies;
