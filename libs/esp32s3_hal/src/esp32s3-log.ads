with Interfaces;

--  Tiny console-logging shim for bare-metal examples.
--
--  Formatted output without a hosted runtime: there is no Ada.Text_IO console on
--  this target, so this routes through the ROM printf via four fixed-signature C
--  wrappers (hal_log_* in examples/common/bare/bare_log.c, linked into every
--  example).  Examples can then format in Ada -- Put a String, an Integer, an
--  unsigned, or hex -- instead of hand-writing a glue.c helper per message.
--
--  Strings are passed to C NUL-terminated (built in a small stack buffer), so no
--  secondary stack or heap is used and the package is light enough for the
--  embedded/ZFP profiles.
package ESP32S3.Log is

   --  Write a string (no newline).
   procedure Put (S : String);

   --  Write a string then a newline (just a newline when S is omitted/empty).
   procedure Put_Line (S : String := "");

   --  Write a newline.
   procedure New_Line;

   --  Write a signed decimal integer.
   procedure Put (N : Integer);

   --  Write an unsigned decimal integer.
   procedure Put_Unsigned (N : Interfaces.Unsigned_32);

   --  Write N in lowercase hexadecimal (no "0x" prefix, no leading zeros).
   procedure Put_Hex (N : Interfaces.Unsigned_32);

end ESP32S3.Log;
