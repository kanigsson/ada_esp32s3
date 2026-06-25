--  SPARKNaCl known-answer tests on the bare-metal ESP32-S3.
--
--  Proves the vendored, formally-verified SPARKNaCl crypto primitives compute
--  correct results on this target -- the foundation for a pure-Ada TLS stack.
--  Each check compares a primitive's output against a published test vector.
with Ada.Real_Time; use Ada.Real_Time;
with Interfaces;
with SPARKNaCl;
with SPARKNaCl.Hashing.SHA256;
with SPARKNaCl.Scalar;
with ESP32S3.RNG;
with ESP32S3.Log; use ESP32S3.Log;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   use type SPARKNaCl.Byte_Seq;
   subtype Byte_Seq is SPARKNaCl.Byte_Seq;
   subtype Bytes_32 is SPARKNaCl.Bytes_32;

   procedure Check (Name : String; Pass : Boolean) is
   begin
      Put_Line ("[kat] " & Name & " : " & (if Pass then "PASS" else "FAIL"));
   end Check;

   --  SHA-256("abc") (FIPS 180-4 example).
   Abc      : constant Byte_Seq (0 .. 2) := (16#61#, 16#62#, 16#63#);
   SHA_Want : constant Bytes_32 :=
     (16#ba#, 16#78#, 16#16#, 16#bf#, 16#8f#, 16#01#, 16#cf#, 16#ea#,
      16#41#, 16#41#, 16#40#, 16#de#, 16#5d#, 16#ae#, 16#22#, 16#23#,
      16#b0#, 16#03#, 16#61#, 16#a3#, 16#96#, 16#17#, 16#7a#, 16#9c#,
      16#b4#, 16#10#, 16#ff#, 16#61#, 16#f2#, 16#00#, 16#15#, 16#ad#);

   --  X25519 scalar multiplication (RFC 7748 section 5.2, first vector).
   X_Scalar : constant Bytes_32 :=
     (16#a5#, 16#46#, 16#e3#, 16#6b#, 16#f0#, 16#52#, 16#7c#, 16#9d#,
      16#3b#, 16#16#, 16#15#, 16#4b#, 16#82#, 16#46#, 16#5e#, 16#dd#,
      16#62#, 16#14#, 16#4c#, 16#0a#, 16#c1#, 16#fc#, 16#5a#, 16#18#,
      16#50#, 16#6a#, 16#22#, 16#44#, 16#ba#, 16#44#, 16#9a#, 16#c4#);
   X_U : constant Bytes_32 :=
     (16#e6#, 16#db#, 16#68#, 16#67#, 16#58#, 16#30#, 16#30#, 16#db#,
      16#35#, 16#94#, 16#c1#, 16#a4#, 16#24#, 16#b1#, 16#5f#, 16#7c#,
      16#72#, 16#66#, 16#24#, 16#ec#, 16#26#, 16#b3#, 16#35#, 16#3b#,
      16#10#, 16#a9#, 16#03#, 16#a6#, 16#d0#, 16#ab#, 16#1c#, 16#4c#);
   X_Want : constant Bytes_32 :=
     (16#c3#, 16#da#, 16#55#, 16#37#, 16#9d#, 16#e9#, 16#c6#, 16#90#,
      16#8e#, 16#94#, 16#ea#, 16#4d#, 16#f2#, 16#8d#, 16#08#, 16#4f#,
      16#32#, 16#ec#, 16#cf#, 16#03#, 16#49#, 16#1c#, 16#71#, 16#f7#,
      16#54#, 16#b4#, 16#07#, 16#55#, 16#77#, 16#a2#, 16#85#, 16#52#);
begin
   delay until Clock + Milliseconds (200);

   --  Enable a real hardware entropy source (internal 8 MHz clock + SAR ADC
   --  sampling) before using the RNG for anything cryptographic -- required on
   --  this RF-free bare-metal target so the RNG is a CSPRNG, not just jitter.
   ESP32S3.RNG.Enable_Entropy_Source;

   Put_Line ("[kat] SPARKNaCl known-answer tests (pure Ada/SPARK on the S3)");
   Check ("SHA-256(abc)  ", SPARKNaCl.Hashing.SHA256.Hash (Abc) = SHA_Want);
   Check ("X25519 RFC7748", SPARKNaCl.Scalar.Mult (X_Scalar, X_U) = X_Want);

   --  Show the entropy source is live: three RNG words (should all differ).
   Put ("[kat] RNG (entropy on):");
   for K in 1 .. 3 loop
      Put (" ");
      Put_Hex (Interfaces.Unsigned_32 (ESP32S3.RNG.Read), 8);
   end loop;
   New_Line;
   Put_Line ("[kat] done");

   loop delay until Clock + Seconds (3600); end loop;
end Main;
