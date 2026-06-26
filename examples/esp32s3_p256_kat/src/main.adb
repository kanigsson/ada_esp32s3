--  Known-answer test for the pure-Ada P-256 (secp256r1) ECDSA verifier (P256).
--  The vector was produced with OpenSSL (ecparam prime256v1 + dgst -sha256 -sign)
--  and confirmed valid by `openssl dgst -verify`.  We check that P256.Verify
--  accepts the genuine signature and rejects a one-bit-tampered hash.
with Interfaces; use type Interfaces.Unsigned_8;
with ESP32S3.Log; use ESP32S3.Log;
with P256;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   KAT_Qx : constant P256.Bytes_32 :=
     (
      16#A3#, 16#D5#, 16#B9#, 16#BE#, 16#79#, 16#43#, 16#F5#, 16#4F#,
      16#F9#, 16#B8#, 16#8F#, 16#5D#, 16#2E#, 16#82#, 16#51#, 16#C4#,
      16#B9#, 16#1B#, 16#ED#, 16#AE#, 16#E1#, 16#BC#, 16#21#, 16#AD#,
      16#07#, 16#12#, 16#26#, 16#0E#, 16#AE#, 16#79#, 16#99#, 16#1A#);
   KAT_Qy : constant P256.Bytes_32 :=
     (
      16#2E#, 16#A5#, 16#1F#, 16#C1#, 16#3C#, 16#4A#, 16#69#, 16#B1#,
      16#7B#, 16#13#, 16#9B#, 16#57#, 16#67#, 16#E4#, 16#44#, 16#63#,
      16#E0#, 16#1F#, 16#5F#, 16#06#, 16#2E#, 16#1C#, 16#4F#, 16#05#,
      16#9D#, 16#8A#, 16#8E#, 16#75#, 16#30#, 16#1B#, 16#50#, 16#7E#);
   KAT_Hash : constant P256.Bytes_32 :=
     (
      16#0F#, 16#B7#, 16#6E#, 16#5A#, 16#9C#, 16#8D#, 16#DE#, 16#38#,
      16#8D#, 16#06#, 16#56#, 16#55#, 16#26#, 16#17#, 16#EB#, 16#ED#,
      16#E9#, 16#25#, 16#C7#, 16#31#, 16#07#, 16#93#, 16#C4#, 16#E1#,
      16#3C#, 16#54#, 16#91#, 16#05#, 16#72#, 16#CB#, 16#67#, 16#24#);
   KAT_R : constant P256.Bytes_32 :=
     (
      16#1E#, 16#FF#, 16#4D#, 16#52#, 16#69#, 16#2D#, 16#F9#, 16#AB#,
      16#CA#, 16#CC#, 16#E7#, 16#51#, 16#84#, 16#93#, 16#AA#, 16#4C#,
      16#3A#, 16#4A#, 16#3F#, 16#10#, 16#73#, 16#8F#, 16#F7#, 16#58#,
      16#BB#, 16#44#, 16#23#, 16#F0#, 16#27#, 16#6E#, 16#BC#, 16#27#);
   KAT_S : constant P256.Bytes_32 :=
     (
      16#97#, 16#44#, 16#2D#, 16#D3#, 16#4D#, 16#7F#, 16#D0#, 16#DC#,
      16#C5#, 16#45#, 16#EC#, 16#48#, 16#5F#, 16#B5#, 16#8D#, 16#7A#,
      16#EB#, 16#B4#, 16#79#, 16#6A#, 16#3A#, 16#39#, 16#4C#, 16#4F#,
      16#86#, 16#9A#, 16#63#, 16#E5#, 16#B9#, 16#B1#, 16#47#, 16#A8#);
   Bad_Hash : P256.Bytes_32 := KAT_Hash;
   Good, Bad : Boolean;
begin
   Put_Line ("[p256] ECDSA P-256 verify KAT");

   Good := P256.Verify (KAT_Qx, KAT_Qy, KAT_Hash, KAT_R, KAT_S);
   Put_Line ("[p256] genuine signature  -> "
             & (if Good then "VALID (PASS)" else "INVALID (FAIL)"));

   Bad_Hash (0) := Bad_Hash (0) xor 1;                 --  flip one bit of the hash
   Bad := P256.Verify (KAT_Qx, KAT_Qy, Bad_Hash, KAT_R, KAT_S);
   Put_Line ("[p256] tampered hash      -> "
             & (if Bad then "VALID (FAIL)" else "INVALID (PASS)"));

   Put_Line ("[p256] result: " & (if Good and not Bad then "ALL PASS" else "FAILURE"));
   loop null; end loop;
end Main;
