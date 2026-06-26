package body FS_Glue is

   function Cstr (Str : String) return String is
      Result : String (1 .. Str'Length + 1);
   begin
      for I in 1 .. Str'Length loop
         declare
            Char : constant Character := Str (Str'First + I - 1);
         begin
            Result (I) :=
              (if Character'Pos (Char) in 32 .. 126 then Char else '.');
         end;
      end loop;
      Result (Result'Last) := Character'Val (0);
      return Result;
   end Cstr;

   procedure Visit (Name      : String;
                    Ino       : ESP32S3.Ext4.Inode_Number;
                    File_Type : ESP32S3.Ext4.U8) is
      C_Name : aliased constant String := Cstr (Name);
   begin
      Entry_R (C_Name'Address, int (Ino), int (File_Type));
   end Visit;

end FS_Glue;
