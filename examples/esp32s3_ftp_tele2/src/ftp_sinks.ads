with System;
with FTP_Client;

--  Library-level (closure-free) FTP callbacks for the tele2 demo.  FTP_Client's
--  Data_Sink/Data_Source are library-level access types, so the callbacks they
--  point at must be library level too (No_Implicit_Dynamic_Code) -- they cannot
--  be nested in Main.
package FTP_Sinks is

   --  Counting sink: total bytes received (for a binary download you don't want
   --  to print, e.g. a .zip).
   procedure Reset_Count;
   function  Bytes_Seen return Natural;
   procedure Count_Chunk (Ctx : System.Address; Chunk : FTP_Client.Byte_Array);

   --  Printing sink: echo each chunk to the console as text (for a directory
   --  listing).
   procedure Put_Chunk (Ctx : System.Address; Chunk : FTP_Client.Byte_Array);

   --  Upload source: supply Upload_Bytes bytes of a test pattern, once.
   Upload_Bytes : constant := 256;
   procedure Reset_Source;
   procedure Test_Source (Ctx  : System.Address;
                          Buf  : out FTP_Client.Byte_Array;
                          Last : out Natural);

end FTP_Sinks;
