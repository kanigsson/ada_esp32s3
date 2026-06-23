package body FS_Glue is

   function Cstr (Str : String) return String is
      R : String (1 .. Str'Length + 1);
   begin
      for I in 1 .. Str'Length loop
         declare
            Ch : constant Character := Str (Str'First + I - 1);
         begin
            R (I) := (if Character'Pos (Ch) in 32 .. 126 then Ch else '.');
         end;
      end loop;
      R (R'Last) := Character'Val (0);
      return R;
   end Cstr;

   procedure Visit (Name      : String;
                    Ino       : ESP32S3.Ext4.Inode_Number;
                    File_Type : ESP32S3.Ext4.U8) is
      N : aliased constant String := Cstr (Name);
   begin
      Entry_R (N'Address, int (Ino), int (File_Type));
   end Visit;

end FS_Glue;
