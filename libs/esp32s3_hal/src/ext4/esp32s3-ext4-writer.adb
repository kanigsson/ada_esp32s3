with Interfaces; use Interfaces;
with Ada.Unchecked_Deallocation;
with ESP32S3.Ext4.Bitmap;
with ESP32S3.Ext4.Inode;
with ESP32S3.Ext4.Dir;
with ESP32S3.Ext4.Path;
with ESP32S3.Ext4.Block_Cache;

package body ESP32S3.Ext4.Writer is

   type Bytes_Ptr is access Byte_Array;
   procedure Free is new Ada.Unchecked_Deallocation (Byte_Array, Bytes_Ptr);

   procedure Guard (V : Volume.Context) is
   begin
      if V.Read_Only then
         raise Read_Only with "volume mounted read-only";
      end if;
      if V.SB.Has_Csum then
         raise Read_Only with "write to a metadata_csum filesystem not supported";
      end if;
   end Guard;

   --  Free a direct/single-indirect inode's data blocks (+ its indirect block).
   procedure Free_Inode_Blocks (V : in out Volume.Context; CI : Inode.Info);

   -----------------
   -- Create_File --
   -----------------

   function Create_File (V : in out Volume.Context; Dir_Path, Name : String)
      return Inode_Number
   is
      Dir_I : Inode.Info;
      Child : Inode_Number;
      CI    : Inode.Info;
   begin
      Guard (V);
      Inode.Read (V, Path.Resolve (V, Dir_Path), Dir_I);
      if not Inode.Is_Dir (Dir_I) then
         raise Use_Error with "parent is not a directory";
      end if;

      Child := Bitmap.Alloc_Inode (V, As_Dir => False);
      CI := (Mode       => 16#8180#,        --  S_IFREG | 0644
             Size       => 0,
             Flags      => 0,               --  indirect-mapped (no EXTENTS_FL)
             Links      => 1,
             Blocks_512 => 0,
             I_Block    => [others => 0]);
      Inode.Write (V, Child, CI, Fresh => True);

      Dir.Add_Entry (V, Dir_I, Name, Child, Dir.FT_Reg);
      return Child;
   end Create_File;

   -----------------
   -- Write_Small --
   -----------------

   procedure Write_Small (V : in out Volume.Context; N : Inode_Number;
                          Data : Byte_Array)
   is
      BS    : constant Natural := V.SB.Block_Size;
      PPB   : constant Natural := BS / 4;                  --  pointers per block
      N_Blk : constant Natural := (Data'Length + BS - 1) / BS;
      I     : Inode.Info;
      Buf   : Bytes_Ptr := new Byte_Array (0 .. BS - 1);
      Ind   : Block_Number := 0;                           --  single-indirect block
      Meta  : Natural := 0;                                --  indirect metadata blocks
      Ptr   : Byte_Array (0 .. 3);
   begin
      Guard (V);
      if N_Blk > 12 + PPB then
         Free (Buf);
         raise Use_Error with "file too large (single-indirect maximum)";
      end if;

      Inode.Read (V, N, I);
      for B in 0 .. N_Blk - 1 loop
         declare
            Phys : constant Block_Number := Bitmap.Alloc_Block (V);
            Lo   : constant Natural := B * BS;
            Cnt  : constant Natural := Natural'Min (BS, Data'Length - Lo);
         begin
            Buf.all := [others => 0];
            Buf (0 .. Cnt - 1) := Data (Data'First + Lo .. Data'First + Lo + Cnt - 1);
            ESP32S3.Ext4.Block_Cache.Write (V.Cache, Phys, Buf.all);

            if B < 12 then
               Put_U32 (I.I_Block, B * 4, U32 (Phys));
            else
               if Ind = 0 then                             --  first indirect ref
                  Ind  := Bitmap.Alloc_Block (V);
                  Meta := Meta + 1;
                  Buf.all := [others => 0];
                  ESP32S3.Ext4.Block_Cache.Write (V.Cache, Ind, Buf.all);
                  Put_U32 (I.I_Block, 12 * 4, U32 (Ind));
               end if;
               Put_U32 (Ptr, 0, U32 (Phys));
               ESP32S3.Ext4.Block_Cache.Write_At (V.Cache, Ind, (B - 12) * 4, Ptr);
            end if;
         end;
      end loop;

      I.Size       := U64 (Data'Length);
      I.Blocks_512 := U64 (N_Blk + Meta) * U64 (BS / 512);
      Inode.Write (V, N, I, Fresh => False);
      Free (Buf);
   end Write_Small;

   -----------
   -- Mkdir --
   -----------

   procedure Mkdir (V : in out Volume.Context; Dir_Path, Name : String) is
      BS       : constant Natural := V.SB.Block_Size;
      Parent_N : Inode_Number;
      Parent_I : Inode.Info;
      New_N    : Inode_Number;
      Blk      : Block_Number;
      DI       : Inode.Info;
      Buf      : Bytes_Ptr := new Byte_Array (0 .. BS - 1);
   begin
      Guard (V);
      Parent_N := Path.Resolve (V, Dir_Path);
      Inode.Read (V, Parent_N, Parent_I);
      if not Inode.Is_Dir (Parent_I) then
         Free (Buf);
         raise Use_Error with "parent is not a directory";
      end if;

      New_N := Bitmap.Alloc_Inode (V, As_Dir => True);
      Blk   := Bitmap.Alloc_Block (V);

      --  Lay down "." (-> self) and ".." (-> parent), ".." spanning the block.
      Buf.all := [others => 0];
      Put_U32 (Buf.all, 0, U32 (New_N));
      Put_U16 (Buf.all, 4, 12);
      Put_U8  (Buf.all, 6, 1);
      Put_U8  (Buf.all, 7, Dir.FT_Dir);
      Buf (8) := Character'Pos ('.');
      Put_U32 (Buf.all, 12, U32 (Parent_N));
      Put_U16 (Buf.all, 16, U16 (BS - 12));
      Put_U8  (Buf.all, 18, 2);
      Put_U8  (Buf.all, 19, Dir.FT_Dir);
      Buf (20) := Character'Pos ('.');
      Buf (21) := Character'Pos ('.');
      ESP32S3.Ext4.Block_Cache.Write (V.Cache, Blk, Buf.all);
      Free (Buf);

      DI := (Mode       => 16#41ED#,          --  S_IFDIR | 0755
             Size       => U64 (BS),
             Flags      => 0,
             Links      => 2,                  --  "." + the parent's entry
             Blocks_512 => U64 (BS / 512),
             I_Block    => [others => 0]);
      Put_U32 (DI.I_Block, 0, U32 (Blk));
      Inode.Write (V, New_N, DI, Fresh => True);

      Dir.Add_Entry (V, Parent_I, Name, New_N, Dir.FT_Dir);

      Parent_I.Links := Parent_I.Links + 1;    --  the new dir's ".." -> parent
      Inode.Write (V, Parent_N, Parent_I, Fresh => False);
   end Mkdir;

   ------------
   -- Unlink --
   ------------

   procedure Unlink (V : in out Volume.Context; Dir_Path, Name : String) is
      Dir_I : Inode.Info;
      Child : Inode_Number;
      CI    : Inode.Info;
   begin
      Guard (V);
      Inode.Read (V, Path.Resolve (V, Dir_Path), Dir_I);
      if not Inode.Is_Dir (Dir_I) then
         raise Use_Error with "parent is not a directory";
      end if;

      Child := Dir.Lookup (V, Dir_I, Name);
      if Child = 0 then
         raise Name_Error with "no such file: " & Name;
      end if;
      Inode.Read (V, Child, CI);
      if Inode.Is_Dir (CI) then
         raise Use_Error with "is a directory (use Rmdir)";
      end if;

      if CI.Links <= 1 then
         Free_Inode_Blocks (V, CI);
         Bitmap.Free_Inode (V, Child, Was_Dir => False);
         Inode.Mark_Deleted (V, Child);
      else
         CI.Links := CI.Links - 1;
         Inode.Write (V, Child, CI, Fresh => False);
      end if;

      declare
         Removed : constant Inode_Number := Dir.Remove_Entry (V, Dir_I, Name);
         pragma Unreferenced (Removed);
      begin
         null;
      end;
   end Unlink;

   --  ext file_type byte for an inode.
   function FType_Of (CI : Inode.Info) return U8 is
     (if Inode.Is_Dir (CI) then Dir.FT_Dir
      elsif Inode.Is_Symlink (CI) then Dir.FT_Symlink
      else Dir.FT_Reg);

   --  Free a direct / single-indirect inode's data blocks (and its indirect
   --  block).  Double/triple-indirect and extent maps aren't freeable yet.
   procedure Free_Inode_Blocks (V : in out Volume.Context; CI : Inode.Info) is
      BS    : constant Natural := V.SB.Block_Size;
      PPB   : constant Natural := BS / 4;
      N_Blk : constant Natural := Natural ((CI.Size + U64 (BS) - 1) / U64 (BS));
      Ptr   : Byte_Array (0 .. 3);
   begin
      --  A symlink's i_block holds either inline target text (fast symlink, no
      --  data blocks) or a single block pointer (slow symlink) -- never the
      --  classic block map, so it must not run through the loops below.
      if Inode.Is_Symlink (CI) then
         if CI.Blocks_512 /= 0 then               --  slow symlink: one block
            declare
               P : constant U32 := Get_U32 (CI.I_Block, 0);
            begin
               if P /= 0 then
                  Bitmap.Free_Block (V, Block_Number (P));
               end if;
            end;
         end if;
         return;
      end if;

      if Inode.Uses_Extents (CI)
        or else Get_U32 (CI.I_Block, 52) /= 0      --  double indirect
        or else Get_U32 (CI.I_Block, 56) /= 0      --  triple indirect
      then
         raise Unsupported_Feature
           with "free of double/triple-indirect or extent-mapped inode";
      end if;

      for B in 0 .. Natural'Min (N_Blk, 12) - 1 loop
         declare
            Phys : constant U32 := Get_U32 (CI.I_Block, B * 4);
         begin
            if Phys /= 0 then
               Bitmap.Free_Block (V, Block_Number (Phys));
            end if;
         end;
      end loop;

      if N_Blk > 12 then
         declare
            Ind : constant U32 := Get_U32 (CI.I_Block, 48);   --  i_block[12]
         begin
            if Ind /= 0 then
               for K in 0 .. Natural'Min (N_Blk - 12, PPB) - 1 loop
                  ESP32S3.Ext4.Block_Cache.Read_At
                    (V.Cache, Block_Number (Ind), K * 4, Ptr);
                  declare
                     P : constant U32 := Get_U32 (Ptr, 0);
                  begin
                     if P /= 0 then
                        Bitmap.Free_Block (V, Block_Number (P));
                     end if;
                  end;
               end loop;
               Bitmap.Free_Block (V, Block_Number (Ind));
            end if;
         end;
      end if;
   end Free_Inode_Blocks;

   -----------
   -- Rmdir --
   -----------

   procedure Rmdir (V : in out Volume.Context; Dir_Path, Name : String) is
      Parent_N : Inode_Number;
      Parent_I : Inode.Info;
      Child    : Inode_Number;
      CI       : Inode.Info;
   begin
      Guard (V);
      Parent_N := Path.Resolve (V, Dir_Path);
      Inode.Read (V, Parent_N, Parent_I);
      if not Inode.Is_Dir (Parent_I) then
         raise Use_Error with "parent is not a directory";
      end if;

      Child := Dir.Lookup (V, Parent_I, Name);
      if Child = 0 then
         raise Name_Error with "no such directory: " & Name;
      end if;
      Inode.Read (V, Child, CI);
      if not Inode.Is_Dir (CI) then
         raise Use_Error with "not a directory (use Unlink)";
      end if;
      if not Dir.Is_Empty (V, CI) then
         raise Not_Empty with "directory not empty: " & Name;
      end if;

      Free_Inode_Blocks (V, CI);
      Bitmap.Free_Inode (V, Child, Was_Dir => True);
      Inode.Mark_Deleted (V, Child);

      declare
         R : constant Inode_Number := Dir.Remove_Entry (V, Parent_I, Name);
         pragma Unreferenced (R);
      begin
         null;
      end;
      Parent_I.Links := Parent_I.Links - 1;   --  the child's ".." is gone
      Inode.Write (V, Parent_N, Parent_I, Fresh => False);
   end Rmdir;

   ------------
   -- Rename --
   ------------

   procedure Rename (V : in out Volume.Context;
                     Old_Dir, Old_Name, New_Dir, New_Name : String)
   is
      ON, NN  : Inode_Number;
      Old_DI  : Inode.Info;
      New_DI  : Inode.Info;
      Child   : Inode_Number;
      CI      : Inode.Info;
   begin
      Guard (V);
      ON := Path.Resolve (V, Old_Dir);
      NN := Path.Resolve (V, New_Dir);
      Inode.Read (V, ON, Old_DI);
      if ON = NN then
         New_DI := Old_DI;
      else
         Inode.Read (V, NN, New_DI);
      end if;
      if not Inode.Is_Dir (Old_DI) or else not Inode.Is_Dir (New_DI) then
         raise Use_Error with "rename endpoint is not a directory";
      end if;

      Child := Dir.Lookup (V, Old_DI, Old_Name);
      if Child = 0 then
         raise Name_Error with "no such file: " & Old_Name;
      end if;
      if Dir.Lookup (V, New_DI, New_Name) /= 0 then
         raise Use_Error with "rename target already exists: " & New_Name;
      end if;
      Inode.Read (V, Child, CI);

      Dir.Add_Entry (V, New_DI, New_Name, Child, FType_Of (CI));
      declare
         R : constant Inode_Number := Dir.Remove_Entry (V, Old_DI, Old_Name);
         pragma Unreferenced (R);
      begin
         null;
      end;

      --  Moving a directory to a different parent: repoint its ".." and adjust
      --  both parents' link counts.
      if Inode.Is_Dir (CI) and then ON /= NN then
         declare
            Ok : constant Boolean := Dir.Set_Entry_Inode (V, CI, "..", NN);
            NP : Inode.Info;
         begin
            if not Ok then
               raise Corrupt with "directory has no "".."" entry";
            end if;
            Old_DI.Links := Old_DI.Links - 1;
            Inode.Write (V, ON, Old_DI, Fresh => False);
            Inode.Read (V, NN, NP);
            NP.Links := NP.Links + 1;
            Inode.Write (V, NN, NP, Fresh => False);
         end;
      end if;
   end Rename;

   --------------
   -- Truncate --
   --------------

   procedure Truncate (V : in out Volume.Context; N : Inode_Number; New_Size : U64) is
      I      : Inode.Info;
      BS     : constant Natural := V.SB.Block_Size;
      Ptr    : Byte_Array (0 .. 3);
   begin
      Guard (V);
      Inode.Read (V, N, I);
      if not Inode.Is_Reg (I) then
         raise Use_Error with "not a regular file";
      end if;
      if Inode.Uses_Extents (I)
        or else Get_U32 (I.I_Block, 52) /= 0
        or else Get_U32 (I.I_Block, 56) /= 0
      then
         raise Unsupported_Feature with "truncate of double-indirect / extent file";
      end if;

      declare
         Old_NB : constant Natural := Natural ((I.Size   + U64 (BS) - 1) / U64 (BS));
         New_NB : constant Natural := Natural ((New_Size + U64 (BS) - 1) / U64 (BS));
      begin
         if New_NB < Old_NB then
            for B in New_NB .. Old_NB - 1 loop
               if B < 12 then
                  declare
                     Phys : constant U32 := Get_U32 (I.I_Block, B * 4);
                  begin
                     if Phys /= 0 then Bitmap.Free_Block (V, Block_Number (Phys)); end if;
                     Put_U32 (I.I_Block, B * 4, 0);
                  end;
               else
                  declare
                     Ind : constant U32 := Get_U32 (I.I_Block, 48);
                  begin
                     if Ind /= 0 then
                        ESP32S3.Ext4.Block_Cache.Read_At
                          (V.Cache, Block_Number (Ind), (B - 12) * 4, Ptr);
                        declare
                           P : constant U32 := Get_U32 (Ptr, 0);
                        begin
                           if P /= 0 then Bitmap.Free_Block (V, Block_Number (P)); end if;
                        end;
                        Put_U32 (Ptr, 0, 0);     --  clear the freed pointer
                        ESP32S3.Ext4.Block_Cache.Write_At
                          (V.Cache, Block_Number (Ind), (B - 12) * 4, Ptr);
                     end if;
                  end;
               end if;
            end loop;

            if New_NB <= 12 and then Old_NB > 12 then
               declare
                  Ind : constant U32 := Get_U32 (I.I_Block, 48);
               begin
                  if Ind /= 0 then Bitmap.Free_Block (V, Block_Number (Ind)); end if;
                  Put_U32 (I.I_Block, 48, 0);
               end;
            end if;

            declare
               Meta : constant Natural := (if New_NB > 12 then 1 else 0);
            begin
               I.Blocks_512 := U64 (New_NB + Meta) * U64 (BS / 512);
            end;
         end if;
      end;

      I.Size := New_Size;
      Inode.Write (V, N, I, Fresh => False);
   end Truncate;

   ----------
   -- Link --
   ----------

   procedure Link (V : in out Volume.Context;
                   Target_Path, New_Dir, New_Name : String)
   is
      TN  : constant Inode_Number := Path.Resolve (V, Target_Path);
      TI  : Inode.Info;
      NDI : Inode.Info;
   begin
      Guard (V);
      Inode.Read (V, TN, TI);
      if Inode.Is_Dir (TI) then
         raise Use_Error with "hard link to a directory";
      end if;
      Inode.Read (V, Path.Resolve (V, New_Dir), NDI);
      if not Inode.Is_Dir (NDI) then
         raise Use_Error with "link parent is not a directory";
      end if;
      if Dir.Lookup (V, NDI, New_Name) /= 0 then
         raise Use_Error with "link target already exists: " & New_Name;
      end if;
      Dir.Add_Entry (V, NDI, New_Name, TN, FType_Of (TI));
      TI.Links := TI.Links + 1;
      Inode.Write (V, TN, TI, Fresh => False);
   end Link;

   ------------------
   -- Make_Symlink --
   ------------------

   procedure Make_Symlink (V : in out Volume.Context;
                           Dir_Path, Name, Target : String)
   is
      BS    : constant Natural := V.SB.Block_Size;
      Dir_I : Inode.Info;
      Child : Inode_Number;
      CI    : Inode.Info;
   begin
      Guard (V);
      if Target'Length = 0 then
         raise Use_Error with "empty symlink target";
      end if;
      if Target'Length > BS then
         raise Use_Error with "symlink target longer than one block";
      end if;

      Inode.Read (V, Path.Resolve (V, Dir_Path), Dir_I);
      if not Inode.Is_Dir (Dir_I) then
         raise Use_Error with "parent is not a directory";
      end if;
      if Dir.Lookup (V, Dir_I, Name) /= 0 then
         raise Use_Error with "symlink target already exists: " & Name;
      end if;

      Child := Bitmap.Alloc_Inode (V, As_Dir => False);
      CI := (Mode       => 16#A1FF#,         --  S_IFLNK | 0777
             Size       => U64 (Target'Length),
             Flags      => 0,
             Links      => 1,
             Blocks_512 => 0,
             I_Block    => [others => 0]);

      if Target'Length < 60 then
         --  Fast symlink: the link text lives inline in the 60-byte i_block.
         for K in 0 .. Target'Length - 1 loop
            CI.I_Block (K) := Character'Pos (Target (Target'First + K));
         end loop;
         Inode.Write (V, Child, CI, Fresh => True);
      else
         --  Slow symlink: one data block holds the link text.
         declare
            Phys : constant Block_Number := Bitmap.Alloc_Block (V);
            Buf  : Bytes_Ptr := new Byte_Array (0 .. BS - 1);
         begin
            Buf.all := [others => 0];
            for K in 0 .. Target'Length - 1 loop
               Buf (K) := Character'Pos (Target (Target'First + K));
            end loop;
            ESP32S3.Ext4.Block_Cache.Write (V.Cache, Phys, Buf.all);
            Put_U32 (CI.I_Block, 0, U32 (Phys));
            CI.Blocks_512 := U64 (BS / 512);
            Inode.Write (V, Child, CI, Fresh => True);
            Free (Buf);
         end;
      end if;

      Dir.Add_Entry (V, Dir_I, Name, Child, Dir.FT_Symlink);
   end Make_Symlink;

end ESP32S3.Ext4.Writer;
