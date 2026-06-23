with System;
with Interfaces.C; use Interfaces.C;
with ESP32S3.Ext4;

--  Library-level C console glue for the ext4_sdmmc example.  These are declared
--  in a package (not nested in Main) on purpose: the directory-iterator callback
--  passed to ESP32S3.Ext4.FS.Iterate by 'Access calls them, and a callback that
--  references entities nested in Main would make GNAT emit a stack trampoline --
--  which faults on this target's non-executable stack (the HAL forbids that via
--  No_Implicit_Dynamic_Code; see libs/esp32s3_hal/no_dynamic_code.adc).  Keeping
--  the glue library-level makes the callback closure-free.
package FS_Glue is
   procedure Banner;  pragma Import (C, Banner, "native_fs_banner");
   procedure Card_R (Ok : int);  pragma Import (C, Card_R, "native_fs_card");
   procedure Mount_R (Ok, BS : int);  pragma Import (C, Mount_R, "native_fs_mount");
   procedure Entry_R (Name : System.Address; Ino, Ftype : int);
                      pragma Import (C, Entry_R, "native_fs_entry");
   procedure File_R (Ok, Size : int; Preview : System.Address);
                      pragma Import (C, File_R, "native_fs_file");
   procedure Err_R (Stage : System.Address);
                      pragma Import (C, Err_R, "native_fs_err");
   procedure Done;  pragma Import (C, Done, "native_fs_done");

   --  NUL-terminate Str for the C %s glue, replacing non-printables with '.'.
   function Cstr (Str : String) return String;

   --  Directory-iterator callback for ESP32S3.Ext4.FS.Iterate.  It MUST be
   --  library-level (here, not nested in Main): 'Access of a nested subprogram
   --  passed to Iterate's anonymous access-to-subprogram parameter would need a
   --  GNAT stack trampoline, which faults on this non-executable stack.
   procedure Visit (Name      : String;
                    Ino       : ESP32S3.Ext4.Inode_Number;
                    File_Type : ESP32S3.Ext4.U8);
end FS_Glue;
