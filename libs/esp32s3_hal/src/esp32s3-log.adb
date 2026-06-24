with System;
with Interfaces.C;

package body ESP32S3.Log is

   --  Fixed-signature ROM-printf wrappers (examples/common/bare/bare_log.c).
   procedure C_Cstr (S : System.Address);
   pragma Import (C, C_Cstr, "hal_log_cstr");

   procedure C_Int (N : Interfaces.C.int);
   pragma Import (C, C_Int, "hal_log_int");

   procedure C_Uint (N : Interfaces.C.unsigned);
   pragma Import (C, C_Uint, "hal_log_uint");

   procedure C_Hex (N : Interfaces.C.unsigned);
   pragma Import (C, C_Hex, "hal_log_hex");

   ---------
   -- Put --
   ---------

   procedure Put (S : String) is
      --  Copy into a stack buffer and NUL-terminate for C ("%s").
      Buf : String (1 .. S'Length + 1);
   begin
      if S'Length > 0 then
         Buf (1 .. S'Length) := S;
      end if;
      Buf (Buf'Last) := ASCII.NUL;
      C_Cstr (Buf'Address);
   end Put;

   --------------
   -- New_Line --
   --------------

   procedure New_Line is
      NL : aliased constant String := (ASCII.LF, ASCII.NUL);
   begin
      C_Cstr (NL'Address);
   end New_Line;

   --------------
   -- Put_Line --
   --------------

   procedure Put_Line (S : String := "") is
   begin
      Put (S);
      New_Line;
   end Put_Line;

   ---------
   -- Put --
   ---------

   procedure Put (N : Integer) is
   begin
      C_Int (Interfaces.C.int (N));
   end Put;

   ------------------
   -- Put_Unsigned --
   ------------------

   procedure Put_Unsigned (N : Interfaces.Unsigned_32) is
   begin
      C_Uint (Interfaces.C.unsigned (N));
   end Put_Unsigned;

   -------------
   -- Put_Hex --
   -------------

   procedure Put_Hex (N : Interfaces.Unsigned_32) is
   begin
      C_Hex (Interfaces.C.unsigned (N));
   end Put_Hex;

end ESP32S3.Log;
