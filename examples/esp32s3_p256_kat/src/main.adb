--  Known-answer test for the pure-Ada P-256 (secp256r1) ECDSA verifier (P256).
--  The vector was produced with OpenSSL (ecparam prime256v1 + dgst -sha256 -sign)
--  and confirmed valid by `openssl dgst -verify`.  We check that P256.Verify
--  accepts the genuine signature and rejects a one-bit-tampered hash.
with Interfaces; use type Interfaces.Unsigned_8;
with ESP32S3.Log; use ESP32S3.Log;
with P256; use type P256.Bytes;

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
   ECDH_D : constant P256.Bytes_32 :=
     (
      16#D8#, 16#A6#, 16#42#, 16#7E#, 16#87#, 16#E0#, 16#65#, 16#6D#,
      16#1D#, 16#D1#, 16#9C#, 16#AC#, 16#AF#, 16#8E#, 16#D2#, 16#FE#,
      16#50#, 16#D9#, 16#DC#, 16#F0#, 16#01#, 16#F0#, 16#28#, 16#F7#,
      16#71#, 16#73#, 16#DD#, 16#57#, 16#0B#, 16#D1#, 16#18#, 16#18#);
   ECDH_MyX : constant P256.Bytes_32 :=
     (
      16#73#, 16#50#, 16#44#, 16#E7#, 16#FF#, 16#F2#, 16#51#, 16#DA#,
      16#70#, 16#AB#, 16#B6#, 16#A5#, 16#69#, 16#B1#, 16#47#, 16#69#,
      16#CA#, 16#A5#, 16#F3#, 16#0B#, 16#EB#, 16#E0#, 16#D3#, 16#21#,
      16#B2#, 16#5C#, 16#24#, 16#85#, 16#7D#, 16#A5#, 16#D3#, 16#1F#);
   ECDH_MyY : constant P256.Bytes_32 :=
     (
      16#E9#, 16#C9#, 16#50#, 16#E8#, 16#80#, 16#6C#, 16#FD#, 16#93#,
      16#87#, 16#5D#, 16#4A#, 16#3E#, 16#5C#, 16#51#, 16#E0#, 16#FA#,
      16#7A#, 16#4C#, 16#67#, 16#CC#, 16#83#, 16#6F#, 16#D5#, 16#09#,
      16#90#, 16#B9#, 16#B4#, 16#AF#, 16#C8#, 16#CF#, 16#79#, 16#59#);
   ECDH_PeerX : constant P256.Bytes_32 :=
     (
      16#F7#, 16#25#, 16#D5#, 16#E2#, 16#17#, 16#67#, 16#40#, 16#3C#,
      16#33#, 16#48#, 16#EF#, 16#D7#, 16#EA#, 16#5B#, 16#06#, 16#42#,
      16#8F#, 16#12#, 16#0B#, 16#A4#, 16#C6#, 16#79#, 16#42#, 16#31#,
      16#25#, 16#80#, 16#FD#, 16#4A#, 16#65#, 16#0B#, 16#5F#, 16#27#);
   ECDH_PeerY : constant P256.Bytes_32 :=
     (
      16#59#, 16#EA#, 16#42#, 16#FE#, 16#AE#, 16#55#, 16#52#, 16#9F#,
      16#BD#, 16#43#, 16#81#, 16#EE#, 16#72#, 16#3E#, 16#FE#, 16#BA#,
      16#67#, 16#95#, 16#74#, 16#BE#, 16#4F#, 16#D5#, 16#D0#, 16#0B#,
      16#D3#, 16#DF#, 16#21#, 16#C2#, 16#3A#, 16#17#, 16#E3#, 16#20#);
   ECDH_Shared : constant P256.Bytes_32 :=
     (
      16#EB#, 16#23#, 16#AB#, 16#BC#, 16#E9#, 16#5D#, 16#13#, 16#0E#,
      16#03#, 16#BA#, 16#FA#, 16#69#, 16#6F#, 16#E4#, 16#40#, 16#A0#,
      16#4E#, 16#B4#, 16#62#, 16#A6#, 16#C4#, 16#28#, 16#92#, 16#19#,
      16#AC#, 16#05#, 16#9D#, 16#A0#, 16#3C#, 16#67#, 16#71#, 16#4C#);
   PkX, PkY, ShX : P256.Bytes_32;
   Pk_OK, Sh_OK : Boolean;
   Ecdh_Pass : Boolean := False;
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


   --  ECDH: our public key from the private scalar, and the shared secret.
   Pk_OK := P256.Public_Key (ECDH_D, PkX, PkY);
   Put_Line ("[p256] ECDH public key    -> "
             & (if Pk_OK and PkX = ECDH_MyX and PkY = ECDH_MyY
                then "MATCH (PASS)" else "MISMATCH (FAIL)"));
   Sh_OK := P256.ECDH (ECDH_D, ECDH_PeerX, ECDH_PeerY, ShX);
   Put_Line ("[p256] ECDH shared secret -> "
             & (if Sh_OK and ShX = ECDH_Shared then "MATCH (PASS)" else "MISMATCH (FAIL)"));
   Ecdh_Pass := Pk_OK and then PkX = ECDH_MyX and then PkY = ECDH_MyY
                and then Sh_OK and then ShX = ECDH_Shared;

   Put_Line ("[p256] result: "
             & (if Good and not Bad and Ecdh_Pass then "ALL PASS" else "FAILURE"));
   loop null; end loop;
end Main;
