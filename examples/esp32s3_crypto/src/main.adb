--  Ada hardware-crypto self-test (ESP32-S3, no FreeRTOS, no IDF)
--  ===========================================================
--  Exercises the reusable HAL crypto drivers (ESP32S3.SHA, ESP32S3.AES) against
--  published test vectors -- deterministic, so no wiring is needed:
--    * SHA-256("abc")  vs the FIPS-180 example digest;
--    * AES-128 ECB     vs the FIPS-197 example (encrypt), then decrypt back.
with Interfaces;   use Interfaces;
with Interfaces.C; use Interfaces.C;
with Ada.Real_Time; use Ada.Real_Time;

with ESP32S3.SHA;
with ESP32S3.AES;

with System.BB.CPU_Primitives.Multiprocessors;
pragma Unreferenced (System.BB.CPU_Primitives.Multiprocessors);

procedure Main is
   procedure Banner;     pragma Import (C, Banner,  "native_crypto_banner");
   procedure SHA1_R (Ok : int);    pragma Import (C, SHA1_R,  "native_crypto_sha1");
   procedure SHA224_R (Ok : int);  pragma Import (C, SHA224_R, "native_crypto_sha224");
   procedure SHA_R (Ok : int);     pragma Import (C, SHA_R,   "native_crypto_sha");
   procedure AES_E (Ok : int);     pragma Import (C, AES_E,   "native_crypto_aes_enc");
   procedure AES_D (Ok : int);     pragma Import (C, AES_D,   "native_crypto_aes_dec");
   procedure AES256 (Ok : int);    pragma Import (C, AES256,  "native_crypto_aes256");
   procedure Done;       pragma Import (C, Done,    "native_crypto_done");

   use type ESP32S3.SHA.Byte_Array;
   use type ESP32S3.AES.Block;

   --  "abc"
   Abc : constant ESP32S3.SHA.Byte_Array := (16#61#, 16#62#, 16#63#);

   --  FIPS-180 SHA-1("abc")
   Sha1_Expect : constant ESP32S3.SHA.SHA1_Digest :=
     (16#A9#, 16#99#, 16#3E#, 16#36#, 16#47#, 16#06#, 16#81#, 16#6A#,
      16#BA#, 16#3E#, 16#25#, 16#71#, 16#78#, 16#50#, 16#C2#, 16#6C#,
      16#9C#, 16#D0#, 16#D8#, 16#9D#);

   --  FIPS-180 SHA-224("abc")
   Sha224_Expect : constant ESP32S3.SHA.SHA224_Digest :=
     (16#23#, 16#09#, 16#7D#, 16#22#, 16#34#, 16#05#, 16#D8#, 16#22#,
      16#86#, 16#42#, 16#A4#, 16#77#, 16#BD#, 16#A2#, 16#55#, 16#B3#,
      16#2A#, 16#AD#, 16#BC#, 16#E4#, 16#BD#, 16#A0#, 16#B3#, 16#F7#,
      16#E3#, 16#6C#, 16#9D#, 16#A7#);

   --  FIPS-180 SHA-256("abc")
   Sha_Expect : constant ESP32S3.SHA.SHA256_Digest :=
     (16#BA#, 16#78#, 16#16#, 16#BF#, 16#8F#, 16#01#, 16#CF#, 16#EA#,
      16#41#, 16#41#, 16#40#, 16#DE#, 16#5D#, 16#AE#, 16#22#, 16#23#,
      16#B0#, 16#03#, 16#61#, 16#A3#, 16#96#, 16#17#, 16#7A#, 16#9C#,
      16#B4#, 16#10#, 16#FF#, 16#61#, 16#F2#, 16#00#, 16#15#, 16#AD#);

   --  FIPS-197 AES-128 example
   Aes_Key : constant ESP32S3.AES.Key_128 :=
     (16#00#, 16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#,
      16#08#, 16#09#, 16#0A#, 16#0B#, 16#0C#, 16#0D#, 16#0E#, 16#0F#);
   Aes_Plain : constant ESP32S3.AES.Block :=
     (16#00#, 16#11#, 16#22#, 16#33#, 16#44#, 16#55#, 16#66#, 16#77#,
      16#88#, 16#99#, 16#AA#, 16#BB#, 16#CC#, 16#DD#, 16#EE#, 16#FF#);
   Aes_Cipher : constant ESP32S3.AES.Block :=
     (16#69#, 16#C4#, 16#E0#, 16#D8#, 16#6A#, 16#7B#, 16#04#, 16#30#,
      16#D8#, 16#CD#, 16#B7#, 16#80#, 16#70#, 16#B4#, 16#C5#, 16#5A#);

   --  FIPS-197 Appendix C.3 AES-256 example (same plaintext as above).
   Aes_Key_256 : constant ESP32S3.AES.Key_256 :=
     (16#00#, 16#01#, 16#02#, 16#03#, 16#04#, 16#05#, 16#06#, 16#07#,
      16#08#, 16#09#, 16#0A#, 16#0B#, 16#0C#, 16#0D#, 16#0E#, 16#0F#,
      16#10#, 16#11#, 16#12#, 16#13#, 16#14#, 16#15#, 16#16#, 16#17#,
      16#18#, 16#19#, 16#1A#, 16#1B#, 16#1C#, 16#1D#, 16#1E#, 16#1F#);
   Aes_Cipher_256 : constant ESP32S3.AES.Block :=
     (16#8E#, 16#A2#, 16#B7#, 16#CA#, 16#51#, 16#67#, 16#45#, 16#BF#,
      16#EA#, 16#FC#, 16#49#, 16#90#, 16#4B#, 16#49#, 16#60#, 16#89#);
begin
   delay until Clock + Milliseconds (200);
   Banner;

   SHA1_R   (Boolean'Pos (ESP32S3.SHA.Hash_1   (Abc) = Sha1_Expect));
   SHA224_R (Boolean'Pos (ESP32S3.SHA.Hash_224 (Abc) = Sha224_Expect));
   SHA_R    (Boolean'Pos (ESP32S3.SHA.Hash_256 (Abc) = Sha_Expect));

   declare
      C : constant ESP32S3.AES.Block := ESP32S3.AES.Encrypt_ECB (Aes_Key, Aes_Plain);
   begin
      AES_E (Boolean'Pos (C = Aes_Cipher));
      AES_D (Boolean'Pos (ESP32S3.AES.Decrypt_ECB (Aes_Key, Aes_Cipher) = Aes_Plain));
   end;

   --  AES-256: encrypt to the FIPS vector and decrypt back.  (The S3 hardware
   --  has no 192-bit mode, so only 128 and 256 are exercised.)
   AES256 (Boolean'Pos
     (ESP32S3.AES.Encrypt_ECB (Aes_Key_256, Aes_Plain) = Aes_Cipher_256
        and then
      ESP32S3.AES.Decrypt_ECB (Aes_Key_256, Aes_Cipher_256) = Aes_Plain));

   Done;

   loop
      delay until Clock + Seconds (3600);
   end loop;
end Main;
