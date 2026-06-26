--  ext4 WRITE battery for the pure-Ada filesystem on the bare-metal ESP32-S3
--  ==========================================================================
--  What it demonstrates
--    The WRITE + journal (JBD2) API of the pure-Ada filesystem (ESP32S3.Ext4)
--    on a real mkfs.ext4 SD card, over the SDMMC block driver.  It mounts the
--    card read-write and runs the whole battery as ONE journaled transaction:
--      * create a regular file + write it
--      * mkdir a subdirectory + create a file inside it
--      * write a 1 MiB file (forces the single-indirect block map, >12 blocks)
--      * hard link        (two names -> one inode, nlink=2)
--      * symbolic link    (fast/inline symlink)
--      * rename / move
--      * delete (unlink)
--    Each step is asserted on-device; the card then passes 'e2fsck -f' clean on
--    a host, where the tree, the symlink target and the big-file pattern verify.
--
--  Build & run
--    ./x run esp32s3_ext4_write          (./x flash / build take the same name)
--    Embedded profile -- both the FS (block cache) and SDMMC use controlled /
--    secondary-stack resources, and the journal commit allocates a ~64 KB
--    transaction buffer, so build.sh sets ESP32S3_RTS_PROFILE=embedded and puts
--    the heap arena in the 8 MB external PSRAM (HEAP_PSRAM=1).
--
--  Output -- what success looks like
--    A "[ext4w] mount (read-write): OK" line, then one "[PASS]" per operation
--    (cleanup, create, mkdir, file-inside-dir, big file, hard link, symlink,
--    rename, delete), ending with
--      [ext4w] all operations committed (journaled): OK
--    A [FAIL] on any check, or a "write FAILED: ..." line, means the run did not
--    pass; "metadata_csum volume" there means the card was formatted wrong.
--
--  Hardware
--    A FAT-free SD card formatted ext4, whole-device (not a partition) and
--    WITHOUT metadata_csum:
--        mkfs.ext4 -F -O ^metadata_csum /dev/sdX     (/dev/sdX, NOT /dev/sdX1)
--    The pure-Ada FS reads metadata_csum volumes but REFUSES to write them (it
--    does not yet recompute every metadata CRC32c), raising Read_Only -- which
--    this example catches and reports.  Run on a freshly-formatted card; the
--    SDMMC write path is known to drift the free counts when re-run on an
--    already-written volume.
--
--  Wiring -- SDMMC in 1-bit mode, with the card's DAT3/CD driven by a CH422G:
--        SDMMC CLK / CMD / D0 = IO12 / IO11 / IO13   (1-bit)
--        SD DAT3 / CD         = CH422G IO4           (held high)
--        CH422G I2C           = SDA=IO8  SCL=IO9     (I2C0)
with System;
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;
with Ada.Exceptions; use Ada.Exceptions;
with Ada.Unchecked_Deallocation;

with ESP32S3.CH422G;
with ESP32S3.SDMMC;
with ESP32S3.Block_Dev;
with ESP32S3.Block_Dev.SDMMC_Source;
with ESP32S3.Ext4;       use ESP32S3.Ext4;
with ESP32S3.Ext4.FS;
with ESP32S3.Ext4.Inode;
with ESP32S3.Ext4.Bitmap;   --  Phantom_Free_Count tripwire

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   package CH renames ESP32S3.CH422G;
   package SD renames ESP32S3.SDMMC;
   use type CH.Status;
   use type SD.Status;

   procedure Banner;  pragma Import (C, Banner, "native_w_banner");
   procedure Card_R (Ok : int);   pragma Import (C, Card_R, "native_w_card");
   procedure Mount_R (Ok : int);  pragma Import (C, Mount_R, "native_w_mount");
   procedure Write_R (Ok : int; Msg : System.Address);
                      pragma Import (C, Write_R, "native_w_write");
   procedure Step_C (S : System.Address);  pragma Import (C, Step_C, "native_w_step");
   procedure Check_C (L : System.Address; Ok : int);
                      pragma Import (C, Check_C, "native_w_check");
   procedure Done;  pragma Import (C, Done, "native_w_done");

   Expander     : CH.Device;    --  CH422G that drives the card's DAT3/CD
   Expander_Bus : CH.Session;
   Expander_St  : CH.Status;
   SD_Card      : aliased SD.Card;
   SD_St        : SD.Status;

   --  CH422G output byte with bit 4 set: drive its IO4 (the card DAT3/CD) high.
   CH_IO4_High : constant := 2#0001_0000#;

   --  SD High-Speed mode clock ceiling, and the fastest the 1-bit wiring runs
   --  reliably here.
   SD_High_Speed_Clock_Hz : constant := 50_000_000;

   --  A 1 MiB file exercises the single-indirect block map (>12 direct blocks).
   Big_File_Size : constant := 1024 * 1024;
   type Byte_Array_Ptr is access ESP32S3.Ext4.Byte_Array;
   procedure Free is new Ada.Unchecked_Deallocation
     (ESP32S3.Ext4.Byte_Array, Byte_Array_Ptr);

   --  The big file is filled with a repeating, position-dependent byte so the
   --  host (and the on-device head/tail check) can verify the contents exactly.
   --  251 is the largest prime < 256, so the pattern's period (251) is coprime
   --  with the 4 KiB block size -- no block boundary lines up with a repeat,
   --  catching block-map mistakes that a constant fill would hide.
   Pattern_Period : constant := 251;
   function Pattern_Byte (Offset : Natural) return U8 is
     (U8 (Offset mod Pattern_Period));

   --  Printable-ASCII range (space .. tilde); anything outside maps to '.' so a
   --  stray control byte can't corrupt the console line.
   First_Printable : constant := 32;
   Last_Printable  : constant := 126;

   --  Make a NUL-terminated copy of Str for the C "%s" console glue, with
   --  non-printables replaced by '.'.
   function C_String (Str : String) return String is
      Result : String (1 .. Str'Length + 1);   --  + 1 for the trailing NUL
   begin
      for I in 1 .. Str'Length loop
         declare
            Ch : constant Character := Str (Str'First + I - 1);
         begin
            Result (I) :=
              (if Character'Pos (Ch) in First_Printable .. Last_Printable
               then Ch else '.');
         end;
      end loop;
      Result (Result'Last) := Character'Val (0);
      return Result;
   end C_String;

   procedure Step (S : String) is
      Msg : aliased constant String := C_String (S);
   begin
      Step_C (Msg'Address);
   end Step;

   procedure Check (Label : String; Ok : Boolean) is
      Msg : aliased constant String := C_String (Label);
   begin
      Check_C (Msg'Address, Boolean'Pos (Ok));
   end Check;

   procedure Report_Error (Msg_Text : String) is
      Msg : aliased constant String := C_String (Msg_Text);
   begin
      Write_R (0, Msg'Address);
   end Report_Error;

   --  Fill Data with text Str (caller sizes Data to Str'Length).
   procedure Fill (Data : out Byte_Array; Str : String) is
   begin
      for K in Str'Range loop
         Data (Data'First + (K - Str'First)) := Character'Pos (Str (K));
      end loop;
   end Fill;

begin
   --  Let the USB-serial console attach before the first line is printed.
   delay until Clock + Milliseconds (200);
   Banner;

   --  CH422G expander on I2C0 (SDA=IO8 SCL=IO9): drive its IO4 high so the
   --  card's DAT3/CD line is held high.
   CH.Setup (Expander, Sda => 8, Scl => 9);
   CH.Acquire (Expander_Bus, Expander);
   CH.Write_IO (Expander_Bus, CH_IO4_High, Expander_St);
   if Expander_St = CH.OK then
      CH.Configure (Expander_Bus, IO_Dir => CH.Outputs,
                    OC_Mode => CH.Push_Pull, Result => Expander_St);
   end if;

   --  SDMMC slot 1, 1-bit bus, High Speed.
   SD.Setup (SD_Card, On => SD.Slot1, Clk => 12, Cmd => 11, D0 => 13,
             Width => SD.Width_1, Data_Clock_Hz => SD_High_Speed_Clock_Hz,
             High_Speed => True);
   SD.Initialize (SD_Card, SD_St);
   Card_R (Boolean'Pos (SD_St = SD.OK));
   if SD_St /= SD.OK then
      Done;
      --  No card / init failed: nothing more to do -- park forever.
      loop
         delay until Clock + Seconds (3600);
      end loop;
   end if;

   declare
      --  Block cache depth.  The journal commit buffers the whole dirty set, so
      --  this bounds how much metadata a single transaction can touch; 16 blocks
      --  comfortably covers this battery (a file larger than the cache is still
      --  written, but is checkpointed by eviction rather than held to commit).
      Cache_Depth_Blocks : constant := 16;

      Block_Device : constant ESP32S3.Block_Dev.Device :=
             ESP32S3.Block_Dev.SDMMC_Source.Make (SD_Card'Access);
      M  : ESP32S3.Ext4.FS.Mount;   --  the mounted volume

      --  True if Path resolves.  These helpers reference M but are only ever
      --  CALLED directly (never 'Access'd), so no nested-subprogram trampoline.
      function Exists (Path : String) return Boolean is
         Ino : ESP32S3.Ext4.Inode_Number;
         pragma Unreferenced (Ino);
      begin
         Ino := M.Lookup (Path);
         return True;
      exception
         when Name_Error => return False;
      end Exists;

      function Ino_Of (Path : String) return ESP32S3.Ext4.Inode_Number is
      begin
         return M.Lookup (Path);
      exception
         when Name_Error => return 0;
      end Ino_Of;

      --  Best-effort removal so the battery is re-runnable without reformat.
      procedure Try_Unlink (Dir, Name : String) is
      begin
         M.Unlink (Dir, Name);
      exception
         when others => null;
      end Try_Unlink;

      procedure Try_Rmdir (Dir, Name : String) is
      begin
         M.Rmdir (Dir, Name);
      exception
         when others => null;
      end Try_Rmdir;
   begin
      M.Open (Block_Device, Read_Only => False,
              Cache_Blocks => Cache_Depth_Blocks);
      Mount_R (1);
      Bitmap.Reset_Phantom_Free_Count;   --  arm the stale-read / double-free tripwire

      --  0. Remove any leftovers from a previous run.
      Step ("cleanup");
      Try_Unlink ("/", "ada_write.txt");
      Try_Unlink ("/", "ada_hard.txt");
      Try_Unlink ("/", "ada_link");
      Try_Unlink ("/", "ada_renamed.txt");
      Try_Unlink ("/", "ada_big.bin");
      Try_Unlink ("/", "ada_del.txt");
      Try_Unlink ("/", "ada_tmp.txt");
      Try_Unlink ("/ada_dir", "inside.txt");
      Try_Rmdir ("/", "ada_dir");
      M.Commit;

      --  1. A small regular file (the hard-link + symlink target).
      Step ("create /ada_write.txt");
      declare
         Text : constant String :=
           "Written by ESP32-S3 pure-Ada ext4 over SDMMC!" & ASCII.LF;
         Data : Byte_Array (0 .. Text'Length - 1);
      begin
         Fill (Data, Text);
         M.Write_File (M.Create_File ("/", "ada_write.txt"), Data);
      end;
      Check ("create file", Exists ("/ada_write.txt"));

      --  2. A subdirectory with a file inside it.
      Step ("mkdir /ada_dir + file inside");
      M.Mkdir ("/", "ada_dir");
      declare
         Text : constant String := "inside a subdirectory" & ASCII.LF;
         Data : Byte_Array (0 .. Text'Length - 1);
      begin
         Fill (Data, Text);
         M.Write_File (M.Create_File ("/ada_dir", "inside.txt"), Data);
      end;
      declare
         Dir_Info : Inode.Info;
      begin
         M.Stat (M.Lookup ("/ada_dir"), Dir_Info);
         Check ("mkdir (is a directory)", Inode.Is_Dir (Dir_Info));
      end;
      Check ("file inside dir", Exists ("/ada_dir/inside.txt"));

      --  3. A 1 MiB file -> single-indirect block map.
      Step ("write big file /ada_big.bin (1 MiB)");
      declare
         --  Verify the first and last Probe_Bytes of the round-tripped file
         --  (a full 1 MiB compare is left to the host's cmp); the tail probe
         --  reaches past the 12 direct blocks into the single-indirect map.
         Probe_Bytes : constant := 128;

         Big      : Byte_Array_Ptr := new Byte_Array (0 .. Big_File_Size - 1);
         Big_Info : Inode.Info;
         Probe    : Byte_Array (0 .. Probe_Bytes - 1);
         Last     : Natural;
         Ok       : Boolean := True;
      begin
         for Offset in Big'Range loop
            Big (Offset) := Pattern_Byte (Offset);
         end loop;
         M.Write_File (M.Create_File ("/", "ada_big.bin"), Big.all);
         Free (Big);

         M.Stat (M.Lookup ("/ada_big.bin"), Big_Info);
         Ok := Big_Info.Size = U64 (Big_File_Size);

         --  Head: first Probe_Bytes from offset 0.
         M.Read_File (Big_Info, 0, Probe, Last);
         Ok := Ok and then Last = Probe'Length;
         for K in 0 .. Last - 1 loop
            Ok := Ok and then Probe (K) = Pattern_Byte (K);
         end loop;

         --  Tail: last Probe_Bytes of the file.
         M.Read_File (Big_Info, U64 (Big_File_Size - Probe_Bytes), Probe, Last);
         Ok := Ok and then Last = Probe'Length;
         for K in 0 .. Last - 1 loop
            Ok := Ok and then
              Probe (K) = Pattern_Byte (Big_File_Size - Probe_Bytes + K);
         end loop;
         Check ("big file size + head/tail pattern", Ok);
      end;

      --  4. Hard link -> same inode, nlink=2.
      Step ("hard link /ada_hard.txt -> /ada_write.txt");
      M.Link ("/ada_write.txt", "/", "ada_hard.txt");
      declare
         --  A hard link is a second directory entry for the SAME inode, so both
         --  names must resolve to one non-zero inode whose link count is now 2.
         Expected_Link_Count : constant := 2;
         Original_Ino : constant Inode_Number := Ino_Of ("/ada_write.txt");
         Linked_Ino   : constant Inode_Number := Ino_Of ("/ada_hard.txt");
         Link_Info    : Inode.Info;
      begin
         M.Stat (Original_Ino, Link_Info);
         Check ("hard link (same inode, nlink=2)",
                Original_Ino /= 0
                and then Original_Ino = Linked_Ino
                and then Link_Info.Links = Expected_Link_Count);
      end;

      --  5. Symbolic link.  A fast symlink stores the target inline in the inode,
      --  so the inode size equals the target string length.
      Step ("symlink /ada_link -> ada_write.txt");
      M.Symlink ("/", "ada_link", "ada_write.txt");
      declare
         Symlink_Target_Len : constant := 13;   --  "ada_write.txt" is 13 chars
         Symlink_Info : Inode.Info;
      begin
         M.Stat (M.Lookup ("/ada_link"), Symlink_Info);
         Check ("symlink (is a symlink, size=13)",
                Inode.Is_Symlink (Symlink_Info)
                and then Symlink_Info.Size = Symlink_Target_Len);
      end;

      --  6. Rename / move.
      Step ("rename /ada_tmp.txt -> /ada_renamed.txt");
      declare
         Text : constant String := "rename me" & ASCII.LF;
         Data : Byte_Array (0 .. Text'Length - 1);
      begin
         Fill (Data, Text);
         M.Write_File (M.Create_File ("/", "ada_tmp.txt"), Data);
      end;
      M.Rename ("/", "ada_tmp.txt", "/", "ada_renamed.txt");
      Check ("rename (old gone, new present)",
             not Exists ("/ada_tmp.txt") and then Exists ("/ada_renamed.txt"));

      --  7. Delete (unlink).
      Step ("delete /ada_del.txt");
      declare
         Text : constant String := "delete me" & ASCII.LF;
         Data : Byte_Array (0 .. Text'Length - 1);
      begin
         Fill (Data, Text);
         M.Write_File (M.Create_File ("/", "ada_del.txt"), Data);
      end;
      M.Unlink ("/", "ada_del.txt");
      Check ("delete (gone)", not Exists ("/ada_del.txt"));

      --  Commit the whole battery as one journaled transaction.
      Step ("commit");
      M.Commit;

      --  TRIPWIRE: the idempotent Free keeps the free count consistent with the
      --  bitmap on an already-clear bit (a double-free, or a stale/incoherent read
      --  from a flaky card) -- but we surface it rather than mask it.  0 on a
      --  healthy card; >0 means stale cleanup reads (suspect the SD card).
      Check ("no phantom frees (count consistent with bitmap)",
             Bitmap.Phantom_Free_Count = 0);
      Write_R (1, System.Null_Address);

   exception
      when ESP32S3.Ext4.Read_Only =>
         Report_Error
           ("metadata_csum volume -- reformat: mkfs.ext4 -O ^metadata_csum");
      when E : others =>
         Report_Error (Exception_Name (E));
   end;

   Done;
   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
