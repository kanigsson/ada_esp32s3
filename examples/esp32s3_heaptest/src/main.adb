--  On-target stress for the Ada (Tlsf_Core) allocator behind the live
--  malloc/free symbols.  Calls malloc/free directly over the real DRAM (or
--  PSRAM, with HEAP_PSRAM=1) heap, with a per-allocation pattern: an overlap or
--  stale pointer corrupts a pattern and is counted.  Reports PASS/FAIL via
--  ESP32S3.Log.
with Interfaces;              use Interfaces;
with Interfaces.C;            use Interfaces.C;
with System;                  use System;
with System.Storage_Elements; use System.Storage_Elements;
with Ada.Real_Time;           use Ada.Real_Time;
with ESP32S3.Log;             use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   function Malloc (N : size_t) return Address;
   pragma Import (C, Malloc, "malloc");
   procedure C_Free (P : Address);
   pragma Import (C, C_Free, "free");

   procedure Fill (A : Address; Sz : Storage_Count; V : Storage_Element) is
      Arr : Storage_Array (1 .. Sz) with Import, Address => A;
   begin
      Arr := (others => V);
   end Fill;

   function Verify (A : Address; Sz : Storage_Count; V : Storage_Element)
                    return Boolean is
      Arr : Storage_Array (1 .. Sz) with Import, Address => A;
   begin
      return (for all B of Arr => B = V);
   end Verify;

   Seed : Unsigned_32 := 2_463_534_242;
   function Rnd (M : Positive) return Natural is
   begin
      Seed := Seed * 1_103_515_245 + 12_345;
      return Natural (Shift_Right (Seed, 8) mod Unsigned_32 (M));
   end Rnd;

   Max_Live : constant := 32;
   type Slot is record
      A   : Address := Null_Address;
      Sz  : Storage_Count := 0;
      Pat : Storage_Element := 0;
   end record;
   Live   : array (1 .. Max_Live) of Slot;
   Bad    : Natural := 0;
   Allocs : Natural := 0;
   Idx    : Natural;
begin
   delay until Clock + Milliseconds (200);
   Put_Line ("[heap] on-target malloc/free stress (Ada Tlsf allocator)");

   for Step in 1 .. 50_000 loop
      Idx := Rnd (Max_Live) + 1;
      if Live (Idx).A = Null_Address then
         declare
            Sz : constant Storage_Count := Storage_Count (Rnd (256) + 1);
            A  : constant Address := Malloc (size_t (Sz));
         begin
            if A /= Null_Address then
               if To_Integer (A) mod 16 /= 0 then
                  Bad := Bad + 1;
               end if;
               Live (Idx) := (A, Sz, Storage_Element (Rnd (256)));
               Fill (A, Sz, Live (Idx).Pat);
               Allocs := Allocs + 1;
            end if;
         end;
      else
         if not Verify (Live (Idx).A, Live (Idx).Sz, Live (Idx).Pat) then
            Bad := Bad + 1;
         end if;
         C_Free (Live (Idx).A);
         Live (Idx) := (Null_Address, 0, 0);
      end if;
   end loop;

   for S of Live loop
      if S.A /= Null_Address then
         if not Verify (S.A, S.Sz, S.Pat) then
            Bad := Bad + 1;
         end if;
         C_Free (S.A);
      end if;
   end loop;

   Put ("[heap] allocs=");
   Put (Allocs);
   Put ("  corruption=");
   Put (Bad);
   Put_Line (if Bad = 0 then "  PASS" else "  *** FAIL ***");

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
