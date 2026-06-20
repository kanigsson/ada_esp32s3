with System;
with Interfaces;

--  The one block-device abstraction the filesystem talks to.  A record of
--  access-to-subprogram + an opaque context (mirrors lwext4's ext4_blockdev
--  vtable): no tagging, no finalization, swappable at run time.  Behind it sit
--  thin adapters -- ESP32S3.Block_Dev.SD_SPI_Source / SDMMC_Source on target,
--  a file-backed device in the host test harness.
--
--  512-byte sectors (the SD logical sector).  The filesystem layers its own
--  (1 KiB .. 64 KiB) block size on top via ESP32S3.Ext4.Block_Cache.
--
--  The primitive Read/Write may RAISE Ada.IO_Exceptions.Device_Error on a
--  hardware/IO failure (the adapters convert the SD driver's Status enum to a
--  raise); the convenience wrappers below also raise on a null/oversize access.
package ESP32S3.Block_Dev is

   type Sector is array (0 .. 511) of Interfaces.Unsigned_8;
   type Sector_Index is new Interfaces.Unsigned_64;

   type Read_Proc  is access procedure
     (Ctx : System.Address; LBA : Sector_Index; Data : out Sector);
   type Write_Proc is access procedure
     (Ctx : System.Address; LBA : Sector_Index; Data : Sector);
   type Count_Func is access function (Ctx : System.Address) return Sector_Index;

   --  A configured backend.  Write = null marks a read-only device.
   type Device is record
      Ctx   : System.Address := System.Null_Address;
      Read  : Read_Proc  := null;
      Write : Write_Proc := null;
      Count : Count_Func := null;
   end record;

   --  True if the device can be written.
   function Writable (Dev : Device) return Boolean is (Dev.Write /= null);

   --  Total number of 512-byte sectors.
   function Sector_Count (Dev : Device) return Sector_Index;

   --  Read / write one sector; raise Device_Error on a missing primitive or an
   --  out-of-range index (Read_Sector) / a read-only device (Write_Sector).
   procedure Read_Sector  (Dev : Device; LBA : Sector_Index; Data : out Sector);
   procedure Write_Sector (Dev : Device; LBA : Sector_Index; Data : Sector);

end ESP32S3.Block_Dev;
