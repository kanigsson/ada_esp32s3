with ESP32S3.Ext4.Volume;

--  High-level mutation: create a regular file and give it contents.  Write
--  support targets filesystems WITHOUT metadata_csum (ext2/3 and ext4 with
--  ^metadata_csum); attempting it on a metadata_csum volume raises Read_Only,
--  since the group-descriptor/bitmap/dir-tail checksums are not yet recomputed.
package ESP32S3.Ext4.Writer is

   --  Create a regular file Name in directory Dir_Path; return its inode number.
   function Create_File (V : in out Volume.Context; Dir_Path, Name : String)
      return Inode_Number;

   --  Set the entire contents of (currently empty) file inode N.  Allocates up
   --  to 12 direct blocks, i.e. up to 12 * block_size bytes (indirect-block
   --  allocation is a later step).
   procedure Write_Small (V : in out Volume.Context; N : Inode_Number;
                          Data : Byte_Array);

   --  Create an empty subdirectory Name in directory Dir_Path (with "."/"..").
   procedure Mkdir (V : in out Volume.Context; Dir_Path, Name : String);

   --  Remove regular file Name from directory Dir_Path; frees its inode + data
   --  blocks when the last link goes.  (Files with indirect/extent maps are not
   --  yet freeable -> Unsupported_Feature.)
   procedure Unlink (V : in out Volume.Context; Dir_Path, Name : String);

   --  Remove empty subdirectory Name from Dir_Path (raises Not_Empty otherwise).
   procedure Rmdir (V : in out Volume.Context; Dir_Path, Name : String);

   --  Rename Old_Name in Old_Dir to New_Name in New_Dir (same or different
   --  directory).  The target must not already exist.  Moving a directory across
   --  parents fixes up its ".." and the two parents' link counts.
   procedure Rename (V : in out Volume.Context;
                     Old_Dir, Old_Name, New_Dir, New_Name : String);

   --  Set regular file inode N's size to New_Size.  Shrinking frees the now-unused
   --  data (+ indirect) blocks; growing just extends the size (sparse).  Direct /
   --  single-indirect only.
   procedure Truncate (V : in out Volume.Context; N : Inode_Number; New_Size : U64);

   --  Create a hard link New_Name in New_Dir to the existing file Target_Path
   --  (not a directory; target must not already exist).
   procedure Link (V : in out Volume.Context;
                   Target_Path, New_Dir, New_Name : String);

end ESP32S3.Ext4.Writer;
