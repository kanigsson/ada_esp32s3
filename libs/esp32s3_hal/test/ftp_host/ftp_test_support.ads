--  Library-level (closure-free) sink/source callbacks + their state for the FTP
--  host test.  FTP_Client's Data_Sink/Data_Source are library-level access types,
--  so the callbacks they point at must be library-level too (the same rule the
--  bare-metal target enforces under No_Implicit_Dynamic_Code) -- they cannot be
--  nested in the test's main procedure.
with System;
with FTP_Client;

package FTP_Test_Support is

   --  Sink: appends every received chunk into a global buffer.
   procedure Reset_Acc;
   function  Acc_String return String;
   procedure Append_Sink (Ctx : System.Address; Chunk : FTP_Client.Byte_Array);

   --  Source: supplies Upload_Text once, then end-of-file.
   procedure Reset_Upload;
   procedure Upload_Source (Ctx  : System.Address;
                            Buf  : out FTP_Client.Byte_Array;
                            Last : out Natural);

   Upload_Text : constant String;

   --  Large-transfer round-trip: stream Big_Bytes of a position-dependent pattern
   --  for STOR (Big_Source), and check a download matches it (Big_Verify) -- so a
   --  multi-chunk upload + read-back can be verified byte-exact without buffering.
   Big_Bytes : constant := 1_048_576;     --  1 MiB
   procedure Big_Reset;
   procedure Big_Source (Ctx  : System.Address;
                         Buf  : out FTP_Client.Byte_Array;
                         Last : out Natural);
   procedure Big_Verify (Ctx : System.Address; Chunk : FTP_Client.Byte_Array);
   function  Big_Count return Natural;     --  bytes checked by Big_Verify
   function  Big_OK    return Boolean;     --  all matched the pattern

private
   Upload_Text : constant String :=
     "uploaded via ftp_client round-trip" & ASCII.LF;

end FTP_Test_Support;
