with Interfaces;
with ESP32S3.Log;

package body FTP_Sinks is

   Count : Natural := 0;       --  bytes seen by Count_Chunk
   Sent  : Natural := 0;       --  bytes already supplied by Test_Source

   procedure Reset_Count is
   begin
      Count := 0;
   end Reset_Count;

   function Bytes_Seen return Natural is (Count);

   procedure Count_Chunk (Ctx : System.Address; Chunk : FTP_Client.Byte_Array) is
      pragma Unreferenced (Ctx);
   begin
      Count := Count + Chunk'Length;
   end Count_Chunk;

   procedure Put_Chunk (Ctx : System.Address; Chunk : FTP_Client.Byte_Array) is
      pragma Unreferenced (Ctx);
   begin
      for B of Chunk loop
         ESP32S3.Log.Put (Character'Val (Natural (B)));
      end loop;
   end Put_Chunk;

   procedure Reset_Source is
   begin
      Sent := 0;
   end Reset_Source;

   procedure Test_Source (Ctx  : System.Address;
                          Buf  : out FTP_Client.Byte_Array;
                          Last : out Natural) is
      pragma Unreferenced (Ctx);
   begin
      Last := 0;
      while Sent < Upload_Bytes and then Last < Buf'Length loop
         --  A simple, verifiable byte pattern (the server discards it anyway).
         Buf (Buf'First + Last) := Interfaces.Unsigned_8 (Sent mod 256);
         Sent := Sent + 1;
         Last := Last + 1;
      end loop;
   end Test_Source;

end FTP_Sinks;
