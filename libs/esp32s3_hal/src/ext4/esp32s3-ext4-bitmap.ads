with ESP32S3.Ext4.Volume;

--  Block and inode allocation via the per-group bitmaps.  Allocation sets the
--  bit, decrements the group + superblock free counts (and bumps used-dirs for a
--  directory inode).  Write-side only -- valid on a filesystem WITHOUT
--  metadata_csum (bitmap/group-descriptor checksums are not recomputed here).
package ESP32S3.Ext4.Bitmap is

   --  Allocate one data block; returns its block number.  Raises No_Space.
   function Alloc_Block (V : in out Volume.Context) return Block_Number;

   --  Allocate one inode; returns its number.  As_Dir bumps the group's
   --  used-dirs count.  Raises No_Space.
   function Alloc_Inode (V : in out Volume.Context; As_Dir : Boolean)
      return Inode_Number;

   --  Release a previously-allocated block / inode (clears the bit, bumps the
   --  group + superblock free counts; Was_Dir decrements used-dirs).
   procedure Free_Block (V : in out Volume.Context; B : Block_Number);
   procedure Free_Inode (V : in out Volume.Context; N : Inode_Number;
                         Was_Dir : Boolean);

end ESP32S3.Ext4.Bitmap;
